-- Interface between transactor and packet buffers
--
-- This module knows nothing about the ipbus transaction protocol
--
-- Dave Newbold, October 2012

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ipbus_trans_decl.all;

entity transactor_if is
  port(
    clk: in std_logic; 
    rst: in std_logic;
    trans_in: in ipbus_trans_in;
    trans_out: out ipbus_trans_out;
    rx_ready: out std_logic; -- New data is available
    rx_next: in std_logic; -- Request for new data from transactor
    tx_data: in std_logic_vector(31 downto 0); -- Packet data from transactor
    tx_we: in std_logic; -- Transactor data valid
    tx_hdr: in std_logic; -- Header word flag from transactor
    tx_err: in std_logic;
    byte_order: out std_logic; -- Controls byte ordering of input and output packet data
    next_pkt_id: out std_logic_vector(15 downto 0); -- Next expected packet ID
    pkt_rx: out std_logic;
    pkt_tx: out std_logic
   );
 
end transactor_if;

architecture rtl of transactor_if is

  constant PROTO_VER: std_logic_vector(3 downto 0) := X"2";

	type state_type is (ST_IDLE, ST_HDR, ST_ID, ST_BODY, ST_DONE);
	signal state: state_type;
	
	signal raddr, waddr, haddr, waddrh: unsigned(addr_width - 1 downto 0);
	signal hlen, blen, rctr, wctr: unsigned(15 downto 0);
	signal id, next_id: unsigned(15 downto 0);
	signal idata: std_logic_vector(31 downto 0);
	signal first, start, order: std_logic;
	signal proto: std_logic_vector(3 downto 0);
  
begin

	start <= trans_in.pkt_rdy and not trans_in.busy;	

	process(clk)
  begin
  	if rising_edge(clk) then
  
  		if rst = '1' then
  			state <= ST_IDLE;
  		else
				case state is

				when ST_IDLE => -- Starting state
					if start = '1' then
						if trans_in.rdata(31 downto 16) = X"0000" then
							state <= ST_ID;
						else
							state <= ST_HDR;
						end if;
					end if;

				when ST_HDR => -- Transfer packet info
					if rctr = hlen then
						state <= ST_ID;
					end if;

				when ST_ID => -- Check packet ID
					if (id = X"0000" or id = next_id) and proto = PROTO_VER and blen > 1 then
						state <= ST_BODY;
					else
						state <= ST_DONE;
					end if;

				when ST_BODY => -- Transfer body
					if (rctr > blen and tx_hdr = '1') or tx_err = '1' then
						state <= ST_DONE;
					end if;

				when ST_DONE => -- Write buffer header
					state <= ST_IDLE;

				end case;
			end if;

		end if;
	end process;

	process(clk)
	begin
		if falling_edge(clk) then
			if state = ST_HDR or state = ST_ID or (state = ST_BODY and rx_next = '1') or (state = ST_IDLE and start = '1') then
				raddr <= raddr + 1;
			elsif state = ST_DONE or rst = '1' then
				raddr <= (others => '0');
			end if;
		end if;
	end process;

	process(clk)
	begin
		if rising_edge(clk) then
			
			if state = ST_IDLE and start = '1' then
				hlen <= unsigned(trans_in.rdata(31 downto 16));
				blen <= unsigned(trans_in.rdata(15 downto 0));
			end if;
			
			if state = ST_HDR or state = ST_ID or (state = ST_BODY and tx_we = '1') then
				waddr <= waddr + 1;
			elsif state = ST_DONE or rst = '1' then
				waddr <= to_unsigned(1, addr_width);
			end if;

			if state = ST_IDLE then
				rctr <= X"0001";
			elsif state = ST_ID then
				rctr <= X"0002";
			elsif state = ST_HDR or (state = ST_BODY and rx_next = '1') then
				rctr <= rctr + 1;
			end if;

			if state = ST_ID then
				wctr <= X"0001";
			elsif state = ST_BODY and tx_we = '1' and first = '0' then
				wctr <= wctr + 1;
			end if;
			
			if tx_hdr = '1' then
				haddr <= waddr;
			end if;
			
			if state = ST_ID then
				first <= '1';
			elsif tx_we = '1' then
				first <= '0';
			end if;
			
			if rst = '1' then
				next_id <= X"0001";
			elsif state = ST_ID and id = next_id and proto = PROTO_VER then
				if next_id = X"ffff" then
					next_id <= X"0001";
				else
					next_id <= next_id + 1;
				end if;
			end if;
			
			if rst = '1' then
				byte_order <= '0';
			elsif state = ST_ID then
				byte_order <= order;
			end if;
			
		end if;
	end process;
	
	rx_ready <= '1' when state = ST_BODY and not (rctr > blen) else '0';
	order <= '1' when trans_in.rdata(31 downto 28) = X"f" else '0';
	id <= unsigned(trans_in.rdata(23 downto 8)) when order = '0' else
		unsigned(trans_in.rdata(15 downto 8) & trans_in.rdata(23 downto 16));
	proto <= trans_in.rdata(31 downto 28) when order = '0' else
		trans_in.rdata(7 downto 4);
		
	idata <= std_logic_vector(hlen) & std_logic_vector(wctr) when state = ST_DONE
		else trans_in.rdata;
		
	waddrh <= (others => '0') when state = ST_DONE else waddr;
	
	trans_out.raddr <= std_logic_vector(raddr);
	trans_out.pkt_done <= '1' when state = ST_DONE else '0';
	trans_out.we <= '1' when state = ST_HDR or (tx_we = '1' and first = '0') or state = ST_DONE or state = ST_ID else '0';
	trans_out.waddr <= std_logic_vector(haddr) when (state = ST_BODY and tx_hdr = '1') else std_logic_vector(waddrh);
	trans_out.wdata <= tx_data when state = ST_BODY else idata;
	
	next_pkt_id <= std_logic_vector(next_id);
	
	pkt_rx <= '1' when state = ST_IDLE and start = '1' else '0';
	pkt_tx <= '1' when state = ST_DONE else '0';
	
end rtl;

