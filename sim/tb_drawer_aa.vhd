-- tb_drawer_aa.vhd -- GHDL testbench for the WU 2-tap beam in vector_drawer.vhd (BW/Gravitar).
-- Same as the Tempest TB but BW's drawer has NO off_screen port.  Drives the accumulator
-- drawer with vectors of several slopes and logs every emitted pixel (x y cover) to
-- tb_aa_pix.txt.  Run TWICE -- pkg_bwidow.WU_AA true vs false (separate GHDL work libs) --
-- then compare: geometry (off positions subset of on), beam (~2x), AA gradient (1..31).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use std.textio.all;
use std.env.all;
use work.pkg_bwidow.all;

entity tb_drawer_aa is end entity;

architecture sim of tb_drawer_aa is
	signal clk      : std_logic := '0';
	signal scale    : std_logic_vector(12 downto 0) := (others=>'0');
	signal rel_x    : std_logic_vector(12 downto 0) := (others=>'0');
	signal rel_y    : std_logic_vector(12 downto 0) := (others=>'0');
	signal zero     : std_logic := '0';
	signal draw     : std_logic := '0';
	signal done     : std_logic;
	signal xout     : std_logic_vector(9 downto 0);
	signal yout     : std_logic_vector(9 downto 0);
	signal aa_cover : std_logic_vector(4 downto 0);
	signal capturing : boolean := false;
begin
	dut: entity work.vector_drawer port map (
		clk=>clk, clk_ena=>'1', scale=>scale, rel_x=>rel_x, rel_y=>rel_y,
		zero=>zero, draw=>draw, done=>done, xout=>xout, yout=>yout, aa_cover=>aa_cover );

	clk <= not clk after 5 ns;

	cap: process(clk)
		file f       : text open write_mode is "tb_aa_pix.txt";
		variable l   : line;
		variable px  : integer := -9999;
		variable py  : integer := -9999;
		variable prevcap : boolean := false;
	begin
		if rising_edge(clk) then
			if capturing and not prevcap then px := -9999; py := -9999; end if;
			if capturing and done='0' then
				if (conv_integer(xout) /= px) or (conv_integer(yout) /= py) then
					px := conv_integer(xout);
					py := conv_integer(yout);
					write(l, px);  write(l, string'(" "));
					write(l, py);  write(l, string'(" "));
					write(l, conv_integer(aa_cover));
					writeline(f, l);
				end if;
			end if;
			prevcap := capturing;
		end if;
	end process;

	stim: process
		procedure do_vec(dx,dy,sc: integer) is
		begin
			wait until done='1' and rising_edge(clk);
			rel_x <= conv_std_logic_vector(dx,13);
			rel_y <= conv_std_logic_vector(dy,13);
			scale <= conv_std_logic_vector(sc,13);
			draw  <= '1';
			wait until rising_edge(clk);
			draw  <= '0';
			wait until done='0';
			capturing <= true;
			wait until done='1';
			capturing <= false;
			wait until rising_edge(clk);
		end procedure;
	begin
		zero <= '1';
		wait for 60 ns;
		zero <= '0';
		wait until done='1';
		do_vec(200, 40, 64);
		do_vec( 40,200, 64);
		do_vec(150,150, 64);
		do_vec(255,  0, 64);
		do_vec(  0,255, 64);
		do_vec(180, 90, 64);
		wait for 200 ns;
		report "tb_drawer_aa (BW) finished";
		stop;
	end process;
end architecture;
