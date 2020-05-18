library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;
	 use ieee.numeric_std.all;
	 
-- Periode 10us => 100KHz
entity MUDL is
	generic(freqdiv : integer := 10); --Periode Clock * freqdiv
	port(	Input	: in string(1 to 16) := (Others => '0');
			S_GD	: in std_logic := '0';
			S_P	: in std_logic := '0';
			clk,rst: in std_logic := '0';
			Servo	: out std_logic := '0';
			lcd	: out string(1 to 8) := (Others => '0'));
end MUDL;

architecture a_MUDL of MUDL is

Component RAM IS
	PORT
	(
		address		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		wren		: IN STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
END Component;

type state_type is (rsts, idle, check, welcome, nama, unlock, lock, chkdoor, deny);
signal state, next_state : state_type := rsts;

constant db_doorlock	:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(224, 8)); 
constant db_input		:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(232, 8));
constant db_welcome	:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(240, 8));
constant db_denied	:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(248, 8));
constant db_id			:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0, 8));
constant db_name		:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(72, 8));
constant std_timer	: 	integer := 50; --Standard Timer (Timer = Periode Clock * freqdiv * std_timer)

signal dptr 	: std_logic_vector(7 downto 0); --Data Pointer
signal dptr_d	: std_logic_vector(7 downto 0); --Data Pointer Last (Dump)
signal dptr_in	: std_logic_vector(7 downto 0); --Data Pointer Access RAM
signal outram	: std_logic_vector(7 downto 0); --Output RAM
signal c_word	: integer := 0; 		--Counter WORD
signal c_block	: integer := 0; 		--Counter Memory Block
signal timer	: integer := 0;		--TH Timer Initial Value
signal timer_c	: integer := 0;		--TL Timer Counter
signal timer_i	: boolean := false;	--TF Timer Flags
signal timer_en: boolean := false;	--TR Timer Enable
signal print_en: boolean := false;	--LCD Printer Enable
signal check_en: boolean := false;	--ID Check Enable
signal check_i	: boolean := false;	--ID Check Flag (Jika berbeda, Interrupt)
signal idlestr	: boolean := false; 	--LCD Idle Mode true (input) , false (doorlock)
signal sgd_bool: boolean := false;	--Register Sensor Gagang Pintu Dalam
signal servo_d : integer := 0; 		--Servo Mode 1 (LOCK), 2 (UNLOCK)
signal nclk		: std_logic := '1';	--Negasi Clock
signal lstr		: string(1 to 16);	--Last ID Input (Dump)
signal hiword 	: std_logic_vector(7 downto 0);	--Hiword ID (Digit1 WORD)
signal loword 	: std_logic_vector(7 downto 0);	--Loword ID (Digit0 WORD)

function CONVC(SLV8 :STD_LOGIC_VECTOR (7 downto 0)) return CHARACTER is 
	constant XMAP :INTEGER :=0;
	variable TEMP :INTEGER :=0;
begin
	for i in SLV8'range loop
		TEMP:=TEMP*2;
		case SLV8(i) is
		  when '0' | 'L'  => null;
		  when '1' | 'H'  => TEMP :=TEMP+1;
		  when others     => TEMP :=TEMP+XMAP;
		end case;
		end loop;
	return CHARACTER'VAL(TEMP);
end CONVC;

function conv(CHAR :CHARACTER) return STD_LOGIC_VECTOR is
	variable SLV8 :STD_LOGIC_VECTOR (7 downto 0);
	variable TEMP :INTEGER :=CHARACTER'POS(CHAR);
begin
	for i in SLV8'reverse_range loop
		case TEMP mod 2 is
		  when 0 => SLV8(i):='0';
		  when 1 => SLV8(i):='1';
		  when others => null;
		end case;
		TEMP:=TEMP/2;
	end loop;
	return SLV8;
end CONV;

begin

nclk <= not clk;
RAM_INT	: RAM port map(dptr_in, nclk, (others => '0'),  '0', outram);


UTAMA	: process(clk, rst) --CLOCK
begin
	if(rst = '1') then
		state <= rsts;
	elsif(rising_edge(clk)) then
		state <= next_state;
	end if;
end process;

FSM_P	: process(clk) --FSM MEALY
begin
		case state is
			when rsts 	=>
				timer_en <= false;
				next_state <= idle;
			when idle	=>
				if(s_gd = '1') then
					next_state <= unlock;
					sgd_bool <= true;
					timer_en <= false;
				elsif(input /= lstr and input(1) /= '0') then
					next_state <= check;
					dptr <= db_id;
					check_en <= true;
					lstr <= input;
					c_block <= 0;
				elsif(timer_en = false) then
					timer_en <= true;
					timer <= std_timer;
					if(idlestr) then
						dptr <= db_doorlock;
					else
						dptr <= db_input;
					end if;
				elsif(timer_i = true) then
					timer_en <= false;
					idlestr <= not idlestr;
				end if;
			when check	=>
				if(input(1 to 8) = "75461000") then
					if(c_word > 0 and c_word <= 4) then
						hiword <= conv(input(9 + (2*(c_word-1)))) - 48;
						loword <= conv(input(10 + (2*(c_word-1)))) - 48;
					end if;
					if(clk = '1') then
						if(c_word = 1) then
							check_i <= false;
						elsif(c_Word > 5) then
							next_state <= unlock;
							timer_en <= false;
							check_en <= false;
						elsif(c_block > 18) then
							next_state <= deny;
							timer_en <= false;
							check_en <= false;
							c_block <= 0;
						elsif(c_word >= 2 and check_i = false) then
							if((hiword(3 downto 0) & loword(3 downto 0)) /= outram) then
								c_block <= c_Block + 1;
								dptr <= dptr + 4;
								check_i <= true;
							end if;
						end if;
					end if;
				else
					next_state <= deny;
					timer_en <= false;
					check_en <= false;
				end if;
			when welcome=>
				timer <= std_timer;
				timer_en <= true;
				dptr <= db_welcome;
				if(timer_i = true) then
					next_state <= nama;
					timer_en <= false;
					timer_en <= false;
				else
					next_state <= welcome;
				end if;
			when nama	=>
				timer <= std_timer*2;
				timer_en <= true;
				dptr <= db_name + 8*(c_block-1);
				if(timer_i = true) then
					next_state <= lock;
					timer_en <= false;
				elsif(S_P = '1') then
					next_state <= chkdoor;
				else
					next_state <= nama;
				end if;
			when unlock	=>
				timer <= std_timer;
				timer_en <= true;
				if(S_P = '1' and s_gd = '1') then
					next_state <= chkdoor;
				elsif(s_gd = '0') then
					next_state <= welcome;
					timer_en <= false;
				else next_state <= unlock;
				end if;
			when lock	=>
				timer <= std_timer;
				timer_en <= true;
				if(timer_i) then
					next_state <= idle;
				else next_state <= lock;
				end if;
			when chkdoor=>
				timer_en <= false;
				if(S_P = '0' and s_gd = '0') then
					next_state <= lock;
					timer_en <= false;
				else
					next_state <= chkdoor;
				end if;
			when deny	=>
				timer <= std_timer;
				timer_en <= true;
				dptr <= db_denied;
				if(timer_i and (input /= lstr)) then
					next_state <= idle;
				end if;
		end case;
end process;

FSM_O	: process(state) --FSM MOORE OUTPUT
begin
	case state is
		when rsts 	=>	
			print_en <= false;
			servo_d <= 0;
		when idle	=>
			print_en <= true;
			servo_d <= 0;
		when check	=>
			print_en <= false;
			servo_d <= 0;
		when welcome=>
			print_en <= true;
		when nama	=>
			servo_d <= 0;
			print_en <= true;
		when unlock	=>
			print_en <= false;
			servo_d <= 2;
		when lock	=>
			print_en <= false;
			servo_d <= 1;
		when chkdoor=>
			print_en <= false;
		when deny	=>
			print_En <= true;
	end case;
end process;

TIMERP: process(clk) --TIMER
begin
	if(rising_edge(clk)) then
		if(timer_en and not timer_i) then
			timer_C <= timer_c + 1;
			if(timer_c >= timer * freqdiv) then
				timer_i <= true;
			end if;
			if(servo_d > 0) then
				if(timer_c mod 20 >= servo_D) then
					servo <= '0';
				else
					servo <= '1';
				end if;
			end if;
		elsif(timer_i and servo_d > 0) then
			servo <= '0';
		end if;
	end if;
	if(not timer_en) then
		timer_C <= 0;
		timer_i <= false;
		servo <= '0';
	end if;
end process;


ACCRAM: process(clk) --ACCESS RAM
begin
	if(rising_edge(clk)) then
		if(dptr /= dptr_d) then
			dptr_d <= dptr;
			c_word <= 1;
			dptr_in <= dptr;
		elsif(c_word > 0 and c_word <= 8) then
			c_word <= c_word + 1;
			dptr_in <= dptr + c_word;
			if(print_en) then
				lcd(c_Word) <= convc(outram);
			end if;
		end if;
	end if;
end process;


end a_MUDL;