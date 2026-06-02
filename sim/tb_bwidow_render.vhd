-- tb_bwidow_render.vhd -- capture a Black Widow / Gravitar AVG vector frame to
-- bwidow_frame.txt for the FB replay (sim/fb).  Streams the real ROM (bwidow_dl.hex
-- or gravitar_dl.hex), lets the 6502 boot + run the attract, then writes every lit
-- beam point as "ax ay rgb az" lines.  A vggo/halt cadence monitor reports when the
-- AVG is actually cycling (so we can place the capture window on the live attract).
--
-- Run: ghdl -r tb_bwidow_render -gHEXFILE=bwidow_dl.hex -gCAP_LO_US=40000 \
--        -gCAP_HI_US=70000 --stop-time=72ms
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_bwidow_render is
	generic (
		HEXFILE   : string  := "bwidow_dl.hex";
		CAP_LO_US : integer := 40000;   -- capture window start (us)
		CAP_HI_US : integer := 70000;   -- capture window end (us)
		CAPALL    : integer := 0;       -- 1 = capture ALL beam-move points (geometry), not just lit
		COIN_AT_US: integer := 0        -- >0 = pulse COIN then START at this time (control-path test)
	);
end entity;

architecture sim of tb_bwidow_render is
	signal clk      : std_logic := '0';
	signal reset_h  : std_logic := '1';
	signal dn_addr  : std_logic_vector(15 downto 0) := (others => '0');
	signal dn_data  : std_logic_vector(7 downto 0)  := (others => '0');
	signal dn_wr    : std_logic := '0';
	signal in0, in3, in4 : std_logic_vector(7 downto 0) := x"FF";  -- idle (active-low)
	signal sw_b4, sw_d4  : std_logic_vector(7 downto 0) := x"FF";  -- DIP defaults
	signal ax, ay   : std_logic_vector(9 downto 0);
	signal az       : std_logic_vector(7 downto 0);
	signal beam     : std_logic;
	signal rgb      : std_logic_vector(2 downto 0);
	signal snd      : std_logic_vector(7 downto 0);
	signal frame_done, start_frame : std_logic;
	signal dbg      : std_logic_vector(15 downto 0);
	constant CLK_PERIOD : time := 83 ns;   -- 12 MHz (BW native)
begin
	dut: entity work.bwidow port map (
		reset_h => reset_h, clk => clk, pause_h => '0',
		analog_sound_out => snd,
		analog_x_out => ax, analog_y_out => ay, analog_z_out => az,
		BEAM_ENA => beam, rgb_out => rgb,
		start_frame => start_frame, frame_done => frame_done,
		SW_B4 => sw_b4, SW_D4 => sw_d4,
		dn_addr => dn_addr, dn_data => dn_data, dn_wr => dn_wr,
		input_0 => in0, input_3 => in3, input_4 => in4,
		dbg => dbg,
		hs_address => (others=>'0'), hs_data_out => open,
		hs_data_in => (others=>'0'), hs_write => '0'
	);
	clk <= not clk after CLK_PERIOD/2;

	stim: process
		file f       : text open read_mode is HEXFILE;
		variable l   : line;
		variable bv  : std_logic_vector(7 downto 0);
		variable idx : integer := 0;
	begin
		reset_h <= '1';  dn_wr <= '0';
		for i in 0 to 20 loop wait until rising_edge(clk); end loop;
		while not endfile(f) loop
			readline(f, l); hread(l, bv);
			dn_addr <= std_logic_vector(to_unsigned(idx, 16));
			dn_data <= bv; dn_wr <= '1';
			wait until rising_edge(clk); idx := idx + 1;
		end loop;
		dn_wr <= '0';
		report "download complete: " & integer'image(idx) & " bytes (" & HEXFILE & ")";
		for i in 0 to 60 loop wait until rising_edge(clk); end loop;
		reset_h <= '0';
		report "reset released @ " & time'image(now);
		-- CONTROL-PATH TEST: drive a coin then start (active-low; idle=FF).
		--   coin   = input_0 bit1 (m_coin)   -> in0 = x"FD"
		--   start1 = input_4 bit5 (m_start1) -> in4 = x"DF"
		-- If the inputs reach the CPU, BW registers a credit + starts a game (the display
		-- list changes from the attract) -> proves the control wiring end-to-end.
		if COIN_AT_US > 0 then
			wait for COIN_AT_US * 1 us;
			report ">>> COIN pressed @ " & time'image(now);
			in0 <= x"FD"; wait for 50 ms; in0 <= x"FF";
			wait for 10 ms;
			report ">>> START pressed @ " & time'image(now);
			in4 <= x"DF"; wait for 50 ms; in4 <= x"FF";
		end if;
		wait;
	end process;

	-- AVG frame cadence: count vggo (start_frame) rising edges + halt transitions; report
	-- the first few + every 20th so we can see WHEN the attract list starts cycling.
	fcad: process
		variable lastgo, lasthalt : std_logic := '0';
		variable ngo, nhalt : integer := 0;
	begin
		wait until reset_h = '0';
		loop
			wait until rising_edge(clk);
			if start_frame='1' and lastgo='0' then
				ngo := ngo + 1;
				if ngo <= 6 or (ngo mod 20)=0 then
					report "t=" & time'image(now) & "  VGGO #" & integer'image(ngo)
						& "  halts=" & integer'image(nhalt); end if;
			end if;
			lastgo := start_frame;
			if frame_done='1' and lasthalt='0' then nhalt := nhalt + 1; end if;
			lasthalt := frame_done;
		end loop;
	end process;

	-- Frame capture: every lit beam point in [CAP_LO,CAP_HI] -> bwidow_frame.txt
	cap: process
		file f : text open write_mode is "bwidow_frame.txt";
		variable l : line;
		variable n : integer := 0;
		variable beam_cnt, axchg : integer := 0;
		variable rgbmax, azmax : integer := 0;
		variable axmin, axmax, aymin, aymax : integer := 99999;
		variable lax : std_logic_vector(9 downto 0) := (others=>'X');
		variable ix, iy : integer;
	begin
		wait until reset_h = '0';
		wait for CAP_LO_US * 1 us;
		report "=== frame capture START @ " & time'image(now) & " ===";
		axmax:=-1; aymax:=-1;
		while now < CAP_HI_US * 1 us loop
			wait on ax, ay for 5 us;
			if ax /= lax then axchg := axchg + 1; lax := ax; end if;
			ix := to_integer(unsigned(ax)); iy := to_integer(unsigned(ay));
			if ix<axmin then axmin:=ix; end if; if ix>axmax then axmax:=ix; end if;
			if iy<aymin then aymin:=iy; end if; if iy>aymax then aymax:=iy; end if;
			if to_integer(unsigned(rgb))>rgbmax then rgbmax:=to_integer(unsigned(rgb)); end if;
			if to_integer(unsigned(az))>azmax then azmax:=to_integer(unsigned(az)); end if;
			if beam='1' then beam_cnt := beam_cnt + 1; end if;
			if (beam='1' or CAPALL=1) and n < 400000 then
				write(l, ix); write(l, string'(" ")); write(l, iy); write(l, string'(" "));
				write(l, to_integer(unsigned(rgb))); write(l, string'(" "));
				write(l, to_integer(unsigned(az))); writeline(f, l);
				n := n + 1;
			end if;
		end loop;
		report "=== frame capture DONE: " & integer'image(n) & " lit points ===";
		report "  diag: beam_hi=" & integer'image(beam_cnt) & " ax_changes=" & integer'image(axchg)
			& " rgb_max=" & integer'image(rgbmax) & " az_max=" & integer'image(azmax);
		report "  diag: ax[" & integer'image(axmin) & ".." & integer'image(axmax) & "] ay["
			& integer'image(aymin) & ".." & integer'image(aymax) & "]";
		std.env.stop;
	end process;

	-- CPU/clock liveness probe: is ena_1_5M pulsing (clkdiv escaped 'U'?), is the 6502
	-- address bus moving (running?), and does the CPU ever kick avg_go (reach the draw loop)?
	probe: process
		alias caddr is << signal .tb_bwidow_render.dut.c_addr : std_logic_vector(23 downto 0) >>;
		alias agox  is << signal .tb_bwidow_render.dut.avg_go : std_logic >>;
		alias irql  is << signal .tb_bwidow_render.dut.c_irq_l : std_logic >>;
		variable lgo  : std_logic := '0';
		variable lirq : std_logic := '1';
		variable ngo, nirq : integer := 0;
		variable tnext : time := 10 ms;
	begin
		wait until reset_h = '0';
		loop
			wait until rising_edge(clk);
			exit when now >= CAP_HI_US * 1 us;
			if agox='1' and lgo='0' then
				ngo := ngo + 1;
				if ngo<=3 then report "  >>> avg_go #"&integer'image(ngo)&" @ "&time'image(now)
					&" pc=$"&to_hstring(caddr(15 downto 0)); end if;
			end if;
			lgo := agox;
			if irql='0' and lirq='1' then nirq := nirq + 1; end if;
			lirq := irql;
			if now >= tnext then          -- periodic PC sample: is the CPU progressing or stuck?
				report "  [t=" & time'image(now) & "] pc=$" & to_hstring(caddr(15 downto 0))
					& " irqs=" & integer'image(nirq) & " avg_go=" & integer'image(ngo);
				tnext := tnext + 10 ms;
			end if;
		end loop;
		report "PROBE done: irqs=" & integer'image(nirq) & " avg_go=" & integer'image(ngo);
		wait;
	end process;
end architecture;
