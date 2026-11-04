-- Fractional clock enable: CE is high for one clock OUT_CLK times per IN_CLK pulses of IN_CE.
--
-- The accumulator adds OUT_CLK on every IN_CE pulse and, once it reaches the input rate, subtracts it and pulses CE.
-- Every value it takes is a multiple of G = gcd(OUT_CLK, IN_CLK0..IN_CLK3), so it holds the values divided by G:
-- the CE sequence is exactly that of a full-size (32-bit) accumulator, from fewer bits. The rates are generics and G
-- and the width are computed at elaboration, so other clock rates only change the instantiation.
--
-- IN_SEL picks one of up to four input rates (IN_CLK1..3 = 0: same as IN_CLK0) and may change at any clock.
-- IN_OK = '0' makes the input rate 0 (the emu top's input-rate register is 0 in the first clock after power-up).
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY CEGen IS
	GENERIC
	(
		OUT_CLK   : integer := 1;
		IN_CLK0   : integer := 1;
		IN_CLK1   : integer := 0;
		IN_CLK2   : integer := 0;
		IN_CLK3   : integer := 0
	);
	PORT
	(
		CLK       : in  STD_LOGIC;
		RST_N     : in  STD_LOGIC;

		IN_SEL    : in  STD_LOGIC_VECTOR(1 downto 0);
		IN_OK     : in  STD_LOGIC;
		IN_CE     : in  STD_LOGIC;

		CE        : out STD_LOGIC
	);
END CEGen;

ARCHITECTURE SYN OF CEGen IS
	function gcd(a0, b0 : integer) return integer is
		variable a, b, t : integer;
	begin
		a := a0; b := b0;
		for i in 0 to 63 loop
			exit when b = 0;
			t := a mod b; a := b; b := t;
		end loop;
		return a;
	end function;

	function dflt(v, d : integer) return integer is
	begin
		if v = 0 then return d; else return v; end if;
	end function;

	function imax(a, b : integer) return integer is
	begin
		if a > b then return a; else return b; end if;
	end function;

	-- bits to hold 0..v
	function bits(v : integer) return integer is
		variable n : integer;
	begin
		n := 1;
		for i in 1 to 30 loop
			exit when 2**n > v;
			n := n + 1;
		end loop;
		return n;
	end function;

	constant C1 : integer := dflt(IN_CLK1, IN_CLK0);
	constant C2 : integer := dflt(IN_CLK2, IN_CLK0);
	constant C3 : integer := dflt(IN_CLK3, IN_CLK0);
	constant G  : integer := gcd(gcd(gcd(gcd(OUT_CLK, IN_CLK0), C1), C2), C3);
	constant O  : integer := OUT_CLK / G;
	constant I0 : integer := IN_CLK0 / G;
	constant I1 : integer := C1 / G;
	constant I2 : integer := C2 / G;
	constant I3 : integer := C3 / G;
	-- the accumulator stays below max(I0..I3, O) between pulses, so it and the sum fit in W bits
	constant W  : integer := bits(imax(imax(imax(imax(I0, I1), I2), I3), O) + O);

	signal SUM : unsigned(W-1 downto 0) := (others => '0');
	signal INR : unsigned(W-1 downto 0);
BEGIN
	INR <= (others => '0')  when IN_OK = '0'   else
	       to_unsigned(I0, W) when IN_SEL = "00" else
	       to_unsigned(I1, W) when IN_SEL = "01" else
	       to_unsigned(I2, W) when IN_SEL = "10" else
	       to_unsigned(I3, W);

	process( RST_N, CLK )
		variable S : unsigned(W-1 downto 0);
	begin
		if RST_N = '0' then
			SUM <= (others => '0');
			CE <= '0';
		elsif rising_edge(CLK) then
			CE <= '0';
			if IN_CE = '1' then
				S := SUM + to_unsigned(O, W);
				if S >= INR then
					S := S - INR;
					CE <= '1';
				end if;
				SUM <= S;
			end if;
		end if;
	end process;
END SYN;
