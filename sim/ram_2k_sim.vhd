-- Behavioral 1-port RAM substitute for the Altera altsyncram in rtl/ram_2k.vhd.
-- Simulation ONLY (the synthesized build uses the real altsyncram).  Same entity
-- name + port shape so GHDL binds against this and skips the altera_mf dependency.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_2k is
	port (
		address : in  std_logic_vector(10 downto 0);
		clken   : in  std_logic := '1';
		clock   : in  std_logic := '1';
		data    : in  std_logic_vector(7 downto 0);
		wren    : in  std_logic;
		q       : out std_logic_vector(7 downto 0)
	);
end entity;

architecture sim of ram_2k is
	type mem_t is array(0 to 2047) of std_logic_vector(7 downto 0);
	signal mem : mem_t := (others => (others => '0'));
begin
	process(clock)
	begin
		if rising_edge(clock) and clken = '1' then
			if wren = '1' then mem(to_integer(unsigned(address))) <= data; end if;
			q <= mem(to_integer(unsigned(address)));
		end if;
	end process;
end architecture;
