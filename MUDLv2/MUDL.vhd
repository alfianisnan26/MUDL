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
			B_Enter, B_Cancel : in std_logic := '0';
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

type state_type is 	(rsts, idle, check, welcome, nama,
							unlock, lock, chkdoor,deny, sign_in,
							read_ram, write_Ram, admin, admin_check,
							add_id,id_check_add, id_null, add_name, erase_id,id_check_erase, erase_name,
							change_pin, change_Admin, last_Access, write_Admin, mnuadmin,
							done, failed, show_name);
signal state, next_state, true_state, false_state : state_type := rsts;

constant db_id			:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0, 8));
constant db_name		:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(56, 8));
constant db_apin		:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(168, 8));
constant db_mnuadmin	: 	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(176, 8));
constant db_done		: 	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(184, 8));
constant db_adminpin	: 	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(192, 8));
constant db_failed	:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(200, 8));
constant db_unknown	:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(208, 8));
constant db_register	:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(216, 8));
constant db_doorlock	:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(224, 8)); 
constant db_input		:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(232, 8));
constant db_welcome	:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(240, 8));
constant db_denied	:	std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(248, 8));

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
signal check_i	: boolean := false;	--ID Check Flag (Jika berbeda, Interrupt)
signal idlestr	: boolean := false; 	--LCD Idle Mode true (input) , false (doorlock)
signal sgd_bool: boolean := false;	--Register Sensor Gagang Pintu Dalam
signal servo_d : integer := 0; 		--Servo Mode 1 (LOCK), 2 (UNLOCK)
signal nclk		: std_logic := '1';	--Negasi Clock
signal lstr		: string(1 to 8);	--Input RAM buffer
signal linput	: string(1 to 16);	--Last ID Input (Dump)
signal hiword 	: std_logic_vector(7 downto 0);	--Hiword ID (Digit1 WORD)
signal loword 	: std_logic_vector(7 downto 0);	--Loword ID (Digit0 WORD)
signal wren		: std_logic := '0';
signal dinput	: std_logic_vector(7 downto 0) := (others => '0');
signal c_word_rw		: integer := 0;
signal c_block_rw		: integer := 0;
signal wread	: integer := 0;
signal bitset 	: boolean := false;
signal adminid	: integer := 1;
signal lastacc	: integer := 1;
signal enterstate : boolean := false;
signal cancelstate : boolean := false;
signal blockid	: integer := 0;
signal write_i : boolean := false;

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
RAM_INT	: RAM port map(dptr_in, nclk, dinput,  wren, outram);


UTAMA	: process(clk, rst) --CLOCK
begin
	if(rst = '1') then
		state <= rsts;
	elsif(rising_edge(clk)) then
		state <= next_state;
	end if;
end process;

FSM_P	: process(clk) --FSM MEALY
	variable hw	: std_logic_vector(7 downto 0);
	variable lw : std_logic_vector(7 downto 0);
begin
		case state is
			when rsts 	=>
				timer_en <= false;
				next_state <= idle;
			when idle	=>
				c_word_rw <= 8;
				if(s_gd = '1') then
					next_state <= unlock;
					sgd_bool <= true;
					timer_en <= false;
				elsif(input /= linput and input(1) /= '0') then
					next_state <= check;
					timer_en <= false;
					linput <= input;
				elsif(input /= linput and input(1) = '0') then
					linput <= input;
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
					dptr <= db_id;
					lstr <= input(9 to 16);
					c_block <= 0;
					c_word_rw <= 4;
					c_block_rw <= 13;
					next_state <= read_ram;
					false_state <= deny;
					if(b_enter ='1')then
						true_state <= admin_check;
						enterstate<= true;
					else
						true_state <= unlock;
					end if;
				else
					next_state <= deny;
					timer_en <= false;
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
				c_word_rw <= 8;
				timer <= std_timer;
				timer_en <= true;
				lastacc <= c_block;
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
					linput <= input;
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
				c_word_rw <= 8;
				timer <= std_timer;
				timer_en <= true;
				dptr <= db_denied;
				if(timer_i and (input /= linput)) then
					linput <= input;
					next_state <= idle;
				end if;
			when read_ram =>
				if(c_word > 0 and c_word <= c_word_rw) then
					hiword <= conv(lstr(1+(2*(c_word-1)))) - 48;
					loword <= conv(lstr(2+(2*(c_word-1)))) - 48;
				end if;
				if(clk = '1') then
					if(c_word = 1) then
						check_i <= false;
					elsif(wread = c_word_rw) then	
						next_state <= true_state;
					elsif(c_block > c_block_rw) then
						next_state <= false_state;
						c_block <= 0;
					elsif(c_word >= 1 and check_i = false) then
						if(c_word > c_Word_rw) then
							c_block <= c_Block + 1;
							dptr <= dptr + 4;
							check_i <= true;
						end if;
					end if;
				end if;
			when write_Ram =>
				if(c_word > 0 and c_word <= c_word_rw) then
					if(bitset = true) then
						hw := (conv(lstr(1+(2*(c_word-1)))) - 48);
						lw := (conv(lstr(2+(2*(c_word-1)))) - 48);
						dinput <= hw(3 downto 0) & lw(3 downto 0);
					else
						dinput <= conv(lstr(c_word));
					end if;
				end if;
				if(clk = '1') then
					if(c_word = 1) then
						check_i <= false;
					elsif(c_Word > c_word_rw AND check_i = false) then	
						next_state <= true_state;
						timer_en <= false;
						check_i <= true;
					end if;
				end if;
			when admin_check =>
				if(c_block = adminid) then
					next_state <= sign_in;
				else
					next_state <= deny;
				end if;
			when sign_in =>
				c_word_rw <= 8;
				dptr <= db_adminpin;
				if(b_cancel = '1')then
					timer_en <= false;
					next_state <= idle;
					linput <= input;
				elsif(b_enter ='1')then
					lstr(1 to 4) <= input(13 to 16);
					enterstate<= true;
					next_state <= read_ram;
					dptr <= db_apin;
					c_word_rw <= 2;
					c_block_rw <= 1;
					c_block <= 0;
					true_state <= admin;
					false_state <= sign_in;
				end if;
			when admin =>
				c_word_rw <= 8;
				dptr <= db_mnuadmin;
				next_state <= mnuadmin;
				timer_en <= false;
			when mnuadmin =>
				if(b_cancel = '1' and cancelstate = false)then
					timer_en <= false;
					next_state <= idle;
					linput <= input;
					cancelstate <= true;
				elsif(b_cancel = '0' and cancelstate = true) then
					cancelstate <= false;
				elsif(b_enter = '0' and enterstate = true) then
					enterstate <= false;
				elsif(b_enter ='1' and enterstate = false)then
					enterstate<= true;
					timer_en <= false;
					case (input(16)) is
						when '1' =>
							next_state <= add_id;
							c_word_rw <= 8;
							dptr <= db_input;
						when '2' =>
							next_state <= erase_id;
							c_word_rw <= 8;
							dptr <= db_input;
						when '3' =>
							next_state <= change_pin;
							c_word_rw <= 8;
							dptr <= db_input;
						when '4' =>
							next_state <= change_Admin;
							c_word_rw <= 8;
							dptr <= db_input;
						when '5' =>
							next_state <= last_access;
							c_word_rw <= 8;
							dptr <= db_input;
						when others =>
							next_state <= failed;
					end case;
				end if;
			when add_id =>
				if(b_cancel = '1' and cancelstate = false)then
					next_state <= admin;
					cancelstate <= true;
				elsif(b_cancel = '0' and cancelstate = true) then
					cancelstate <= false;
				elsif(b_enter = '0' and enterstate = true) then
					enterstate <= false;
				elsif(b_enter ='1' and enterstate = false)then
					enterstate<= true;
					if(input(1 to 8) = "75461000") then
						dptr <= db_id;
						lstr <= input(9 to 16);
						c_block <= 0;
						c_word_rw <= 4;
						c_block_rw <= 13;
						next_state <= read_ram;
						false_state <= id_check_Add;
						true_state <= failed;
					else
						next_state <= failed;
					end if;
				end if;
			when id_check_add=>
				lstr <= "00000000";
				dptr <= db_id;
				blockid <= c_block;
				c_word_rw <= 4;
				c_block_rw <= 13;
				next_state <= read_ram;
				false_state <= failed;
				true_state <= id_null;
			when id_null=>
				blockid <= c_block;
				dptr <= db_id + (4*(c_block));
				lstr <= input(9 to 16);
				c_word_rw <= 4;
				bitset <= true;
				next_state <= write_Ram;
				true_state <= show_name;
			when show_name =>
				dptr <= db_input;
				c_word_rw <= 8;
				c_block <= 0;
				next_state <= add_name;
			when add_name =>
				if(b_cancel = '1' and cancelstate = false)then
					next_state <= admin;
					cancelstate <= true;
				elsif(b_cancel = '0' and cancelstate = true) then
					cancelstate <= false;
				elsif(b_enter = '0' and enterstate = true) then
					enterstate <= false;
				elsif(b_enter ='1' and enterstate = false)then
					enterstate<= true;
					dptr <= db_name + (8*(blockid));
					lstr <= input(9 to 16);
					c_block <= 0;
					c_word_rw <= 8;
					bitset <= false;
					next_state <= write_Ram;
					true_state <= done;
				end if;
			when erase_id =>
				if(b_cancel = '1' and cancelstate = false)then
					next_state <= admin;
					cancelstate <= true;
				elsif(b_cancel = '0' and cancelstate = true) then
					cancelstate <= false;
				elsif(b_enter = '0' and enterstate = true) then
					enterstate <= false;
				elsif(b_enter ='1' and enterstate = false)then
					enterstate<= true;
					if(input(1 to 8) = "75461000") then
						dptr <= db_id;
						lstr <= input(9 to 16);
						c_block <= 0;
						c_word_rw <= 4;
						c_block_rw <= 13;
						next_state <= read_ram;
						false_state <= failed;
						true_state <= id_check_Erase;
					else
						next_state <= failed;
					end if;
				end if;
			when id_check_erase=>
				blockid <= c_block;
				dptr <= db_id + (4*(c_block-1));
				lstr <= (others => '0');
				c_word_rw <= 4;
				bitset <= true;
				next_state <= write_Ram;
				true_state <= erase_name;
			when erase_name =>
				dptr <= db_name + (8*(blockid	-1));
				lstr <= (others => '0');
				c_word_rw <= 8;
				c_block <= 0;
				bitset <= false;
				next_state <= write_Ram;
				true_state <= done;
			when change_pin =>
				if(b_cancel = '1' and cancelstate = false)then
					next_state <= admin;
					cancelstate <= true;
				elsif(b_cancel = '0' and cancelstate = true) then
					cancelstate <= false;
				elsif(b_enter = '0' and enterstate = true) then
					enterstate <= false;
				elsif(b_enter ='1' and enterstate = false)then
					enterstate<= true;
					bitset <= true;
					dptr <= db_apin;
					lstr <= input(13 to 16) & "0000";
					c_word_rw <= 2;
					next_state <= write_ram;
					true_state <= done;
				end if;
			when change_Admin =>
				if(b_cancel = '1' and cancelstate = false)then
					next_state <= admin;
					cancelstate <= true;
				elsif(b_cancel = '0' and cancelstate = true) then
					cancelstate <= false;
				elsif(b_enter = '0' and enterstate = true) then
					enterstate <= false;
				elsif(b_enter ='1' and enterstate = false)then
					enterstate<= true;
					if(input(1 to 8) = "75461000") then
						dptr <= db_id;
						lstr <= input(9 to 16);
						c_block <= 0;
						c_word_rw <= 4;
						c_block_rw <= 13;
						next_state <= read_ram;
						false_state <= failed;
						true_state <= write_Admin;
					else
						next_state <= failed;
					end if;
				end if;
			when write_Admin =>
				next_state <= done;
				adminid <= c_block;
			when last_Access =>
				dptr <= db_name + 8*(lastacc-1);
				c_Word_rw <= 8;
				if(b_enter = '0' and enterstate = true) then
					enterstate <= false;
				elsif(b_enter ='1' and enterstate = false)then
					enterstate<= true;
					next_state <= admin;
				elsif(b_cancel = '1' and cancelstate = false) then
					next_state <= idle;
					linput <= input;
					cancelstate <= true;
				elsif(b_cancel = '0' and cancelstate = true) then
					cancelstate <= false;
				end if;
			when done =>
				c_word_rw <= 8;
				dptr <= db_done;
				if(b_enter = '0' and enterstate = true) then
					enterstate <= false;
				elsif(b_enter ='1' and enterstate = false)then
					enterstate<= true;
					next_state <= admin;
				elsif(b_cancel ='1' and cancelstate = false)then
					next_state <= idle;
					linput <= input;
					timer_en <= false;
					cancelstate <= true;
				elsif(b_cancel = '0' and cancelstate = true) then
					cancelstate <= false;
				end if;
			when failed =>
				c_word_rw <= 8;
				dptr <= db_failed;
				if(b_enter = '0' and enterstate = true) then
					enterstate <= false;
				elsif(b_enter ='1' and enterstate = false)then
					next_state <= admin;
					enterstate<= true;
				elsif(b_cancel ='1' and cancelstate = false)then
					next_state <= idle;
					linput <= input;
					timer_en <= false;
					cancelstate <= true;
				elsif(b_cancel = '0' and cancelstate = true) then
					cancelstate <= false;
				end if;
		end case;
end process;

WREAD_p : process(clk)
begin
	if(rising_edge(clk))then
		if((hiword(3 downto 0) & loword(3 downto 0)) /= outram) then
			wread <= 0;
		elsif((hiword(3 downto 0) & loword(3 downto 0)) = outram)then
			wread <= wread + 1;
		end if;
	end if;
end process;

FSM_O	: process(state) --FSM MOORE OUTPUT
begin
	case state is
		when rsts 	=>	
			print_en <= false;
			wren <= '0';
			servo_d <= 0;
		when idle	=>
			print_en <= true;
			wren <= '0';
			servo_d <= 0;
		when check	=>
			wren <= '0';
			print_en <= false;
			servo_d <= 0;
		when welcome=>
			print_en <= true;
			wren <= '0';
		when nama	=>
			servo_d <= 0;
			print_en <= true;
			wren <= '0';
		when unlock	=>
			print_en <= false;
			wren <= '0';
			servo_d <= 2;
		when lock	=>
			print_en <= false;
			wren <= '0';
			servo_d <= 1;
		when chkdoor=>
			print_en <= false;
			wren <= '0';
		when deny	=>
			print_En <= true;
			wren <= '0';
		when sign_in =>
			print_En <= true;
			wren <= '0';
		when read_ram =>
			wren <= '0';
		when write_Ram =>
			write_i <= false;
			wren <= '1';
			print_en <= false;
		when admin =>
			print_En <= true;
			wren <= '0';
		when admin_check=>
			print_en <= false;
			wren <= '0';
		when add_id =>
			print_en <= true;
			wren <= '0';
		when id_check_add=>
			print_en <= false;
			wren <= '0';
		when id_null=>
			write_i <= true;
			print_en <= false;
			wren <= '0';
		when add_name =>
			print_en <= true;
			wren <= '0';
		when erase_id =>
			print_en <= true;
			wren <= '0';
		when id_check_erase=>
			write_i <= true;
			print_en <= false;
			wren <= '0';
		when erase_name =>
			print_en <= false;
			wren <= '0';
		when change_pin =>
			print_en <= true;
			wren <= '0';
		when change_Admin =>
			print_en <= true;
			wren <= '0';
		when write_Admin =>
			print_en <= false;
			wren <= '0';
		when last_Access =>
			print_en <= true;
			wren <= '0';
		when done =>
			print_En <= true;
			wren <= '0';
		when failed =>
			print_en <= true;
			wren <= '0';
		when show_name =>
			print_En <= true;
			wren <= '0';
		when mnuadmin =>
			print_en <= true;
			wren <= '0';
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
		if(dptr /= dptr_d or write_i) then
			dptr_d <= dptr;
			c_word <= 1;
			dptr_in <= dptr;
		elsif(c_word > 0 and c_word <= c_word_rw) then
			c_word <= c_word + 1;
			dptr_in <= dptr + c_word;
			if(print_en) then
				lcd(c_Word) <= convc(outram);
			end if;
		end if;
	end if;
end process;


end a_MUDL;