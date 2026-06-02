-- Draws vectors. Gets relative x and y directions and scale, and use these
-- to draw a vector from the starting point. It's supposed to be a workalike
-- for the Atari AVGs analog stuff plus timers plus normalizer, but this
-- implementation differs from it quite a bit. If anything it means the timing
-- probably is way off... hope the software doesn't mind.

-- ToDo: implement something that's a bit closer to reality...
-- ToDo: blank when not actively moving

-- WU beam anti-aliasing (added 2026-06, ported from starwars-videodr0me per
-- docs/HOWTO-vector-AA-port.md).  When pkg_bwidow.WU_AA = true, each accumulator
-- step emits a 2-tap beam instead of one pixel: a bright CORE at the integer pixel
-- plus ONE sub-pixel EDGE on the MINOR axis toward the +fraction, with edge coverage
-- = the Wu fraction (the low bits xpos/ypos(12:0) the integer drawer throws away).
-- The core stays FULL (line never faint); the edge fades in/out with the sub-pixel
-- position => smooth diagonals.  ~2x pixel rate (vs ~3x for a symmetric 3-tap beam);
-- axis-aligned/integer-slope segments (fraction = 0) skip the edge and run at 1x.
-- WU_AA = false is bit-identical to the original integer accumulator (1 px/step).
-- (Tempest HW-confirmed the 2-tap form is flicker-free where the 3-tap was not.)

-- Black Widow arcade hardware implemented in an FPGA
-- (C) 2012 Jeroen Domburg (jeroen AT spritesmods.com)
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

--use ieee_proposed.math_utility_pkg.all;
--use ieee_proposed.fixed_pkg.all;

use work.pkg_bwidow.all;


entity vector_drawer is
    Port ( clk : in  STD_LOGIC;
			  clk_ena: in STD_LOGIC;
           scale : in  STD_LOGIC_VECTOR (12 downto 0);
           rel_x : in  STD_LOGIC_VECTOR (12 downto 0);
           rel_y : in  STD_LOGIC_VECTOR (12 downto 0);
			  zero: in STD_LOGIC;
           draw : in  STD_LOGIC;
			  done : out STD_LOGIC;
           xout : out  STD_LOGIC_VECTOR (9 downto 0);
           yout : out  STD_LOGIC_VECTOR (9 downto 0);
           aa_cover : out STD_LOGIC_VECTOR (4 downto 0)   -- WU beam coverage 0..31 (full=31 when WU_AA off)
	 );
end vector_drawer;

architecture Behavioral of vector_drawer is
	signal xpos: STD_LOGIC_VECTOR(25 downto 0);
	signal ypos: STD_LOGIC_VECTOR(25 downto 0);
	signal normrel_x : STD_LOGIC_VECTOR (12 downto 0);
   signal normrel_y : STD_LOGIC_VECTOR (12 downto 0);
	signal normscale : STD_LOGIC_VECTOR (12 downto 0);
	signal itsdone: std_logic;
	signal normsteps: STD_LOGIC_VECTOR(3 downto 0);
	signal timer: STD_LOGIC_VECTOR(16 downto 0);

	-- ----- WU beam anti-aliasing state -----
	signal wu_tap   : STD_LOGIC_VECTOR(1 downto 0);   -- 0 = core, 1 = sub-pixel edge
	signal primary_x: STD_LOGIC_VECTOR(9 downto 0);   -- integer pixel = pos(22:13)
	signal primary_y: STD_LOGIC_VECTOR(9 downto 0);
	signal absx, absy: STD_LOGIC_VECTOR(12 downto 0); -- |normrel| for major-axis pick
	signal xdom     : STD_LOGIC;                       -- '1' = x is the major axis
	signal frac5    : STD_LOGIC_VECTOR(4 downto 0);    -- minor-axis sub-pixel fraction
	signal tap_x, tap_y : STD_LOGIC_VECTOR(9 downto 0);
	signal tap_cover    : STD_LOGIC_VECTOR(4 downto 0);
begin
	-- ----- combinational AA helpers (free sub-pixel info from the accumulator) -----
	primary_x <= xpos(22 downto 13);
	primary_y <= ypos(22 downto 13);
	absx <= normrel_x when normrel_x(12)='0' else (not normrel_x) + 1;
	absy <= normrel_y when normrel_y(12)='0' else (not normrel_y) + 1;
	xdom <= '1' when absx >= absy else '0';                 -- x major when |dx| >= |dy|
	frac5 <= ypos(12 downto 8) when xdom='1' else xpos(12 downto 8); -- minor-axis fraction

	-- 2-tap beam: CORE at the integer pixel (wu_tap=0) + ONE sub-pixel EDGE on the MINOR
	-- axis toward the +fraction (wu_tap=1).  Core = full; edge coverage = the Wu fraction.
	tap_x <= primary_x       when (wu_tap="00" or xdom='1') else (primary_x + 1);  -- edge on x only if y-major
	tap_y <= primary_y       when (wu_tap="00" or xdom='0') else (primary_y + 1);  -- edge on y only if x-major
	tap_cover <= "11111"     when wu_tap="00" else frac5;                          -- core full, edge = fraction

	process(clk)
	begin
		if clk'event and clk='1' then
			if zero='1' then
				xpos<=(others=>'0');
				ypos<=(others=>'0');
--				itsdone<='1';
				--Remain at (0,0) for a while to give the beam a chance to actually zero out.
				--Implemented by drawing a line with dx=dy=0.
				normsteps<="0000";
				normrel_x<=(others=>'0');
				normrel_y<=(others=>'0');
				timer<=(others=>'0');
				normscale<="0000010000000";
				itsdone<='0';
				wu_tap<="00";
			elsif itsdone='1' then
				if draw='1' then
					--restart drawing the vector
					itsdone<='0';
					normsteps<="1011"; -- 12 bit values can be shifted by 11 at most
					normrel_x<=rel_x;
					normrel_y<=rel_y;
					normscale<=scale;
					timer<=(others=>'0');
					wu_tap<="00";
				end if;
			elsif normsteps/="0000" then
				--Normalize.
				if normrel_x(12)=normrel_x(11) and normrel_y(12)=normrel_y(11) and normscale(0)='0' then
					normsteps<=normsteps-"0001";
					normrel_x(12 downto 1)<=normrel_x(11 downto 0);
					normrel_x(0)<='0';
					normrel_y(12 downto 1)<=normrel_y(11 downto 0);
					normrel_y(0)<='0';
					normscale(11 downto 0)<=normscale(12 downto 1);
					normscale(12)<='0';
				else
					normsteps<="0000";
				end if;
			else
				if timer(16 downto 4)>=normscale then
					itsdone<='1';
					wu_tap<="00";
				else
					if WU_AA then
						-- 2-tap beam: emit CORE (wu_tap=0) then, only if the segment has a real
						-- sub-pixel fraction, the EDGE (wu_tap=1) before advancing.  ~2x pixel
						-- rate; frac5=0 (axis-aligned/integer slope) skips the edge -> 1x.  The
						-- CORE tap lands on exactly the integer-drawer pixel (geometry preserved).
						if wu_tap="00" and frac5/="00000" then
							wu_tap<="01";   -- core done; emit the edge next clk (don't advance yet)
						else
							wu_tap<="00";   -- edge done (or skipped): advance the accumulator
							xpos<=xpos+sxt(normrel_x, xpos'length);
							ypos<=ypos+sxt(normrel_y, ypos'length);
							timer<=timer+"00000000000000100";
						end if;
					else
						-- original integer accumulator: one pixel per clk.
						xpos<=xpos+sxt(normrel_x, xpos'length);
						ypos<=ypos+sxt(normrel_y, ypos'length);
						--timer<=timer+"00000000000000001";
						--timer<=timer+"00000000000000010";
						timer<=timer+"00000000000000100";
					end if;
				end if;
			end if;
		end if;
	end process;
	done <= itsdone;
--	xout <= xpos(23 downto 14);
--	yout <= ypos(23 downto 14);
	-- WU_AA on  -> emit the current 2-tap pixel; off -> bit-identical integer pixel.
	xout     <= tap_x     when WU_AA else primary_x;
	yout     <= tap_y     when WU_AA else primary_y;
	aa_cover <= tap_cover when WU_AA else "11111";   -- full cover when AA disabled
end Behavioral;
