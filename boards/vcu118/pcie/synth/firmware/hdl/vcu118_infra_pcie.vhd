
---------------------------------------------------------------------------------
--
--   Copyright 2017 - Rutherford Appleton Laboratory and University of Bristol
--
--   Licensed under the Apache License, Version 2.0 (the "License");
--   you may not use this file except in compliance with the License.
--   You may obtain a copy of the License at
--
--       http://www.apache.org/licenses/LICENSE-2.0
--
--   Unless required by applicable law or agreed to in writing, software
--   distributed under the License is distributed on an "AS IS" BASIS,
--   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--   See the License for the specific language governing permissions and
--   limitations under the License.
--
--                                     - - -
--
--   Additional information about ipbus-firmare and the list of ipbus-firmware
--   contacts are available at
--
--       https://ipbus.web.cern.ch/ipbus
--
---------------------------------------------------------------------------------


-- Infrastructural firmware for the Xilinx VCU118 board; includes clock configuration, PCIe interface, IPbus transactor & master.
--
-- Tom Williams, July 2018


library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ipbus.all;
use work.ipbus_trans_decl.all;
use work.ipbus_axi_decl.all;

library UNISIM;
use UNISIM.VComponents.all;


entity vcu118_infra_pcie is
    port (
        -- PCIe clock and reset (active low)
        pcie_sys_clk_p : in  std_logic;
        pcie_sys_clk_n : in  std_logic;
        pcie_sys_rst_n : in  std_logic;
        -- PCIe lanes
        pcie_rx_p      : in  std_logic_vector(0 downto 0);
        pcie_rx_n      : in  std_logic_vector(0 downto 0);
        pcie_tx_p      : out std_logic_vector(0 downto 0);
        pcie_tx_n      : out std_logic_vector(0 downto 0);
        -- External oscillator
        osc_clk_p      : in  std_logic;
        osc_clk_n      : in  std_logic;
        -- IPbus clock and reset
        clk_ipb_o      : out std_logic;
        rst_ipb_o      : out std_logic;
        clk_aux_o      : out std_logic;  -- 40MHz generated clock
        rst_aux_o      : out std_logic;
        -- The signals of doom and lesser doom
        nuke           : in  std_logic;
        soft_rst       : in  std_logic;
        -- status LEDs
        leds           : out std_logic_vector(1 downto 0);
        -- IPbus (from / to slaves)
        ipb_in         : in  ipb_rbus;
        ipb_out        : out ipb_wbus
        );
end vcu118_infra_pcie;


architecture rtl of vcu118_infra_pcie is

    signal clk_osc, clk_ipb, clk_ipb_i, clk_aux                                                         : std_logic;
    signal locked, clk_locked, pcie_user_lnk_up, rst125, rst_ipb, rst_aux, rst_ipb_ctrl, rst_axi, onehz : std_logic;

    signal pcie_sys_rst_n_i : std_logic;

    signal axi_ms : axi4mm_ms(araddr(63 downto 0), awaddr(63 downto 0), wdata(63 downto 0));
    signal axi_sm : axi4mm_sm(rdata(63 downto 0));

    signal ipb_pkt_done : std_logic;
    signal trans_in     : ipbus_trans_in;
    signal trans_out    : ipbus_trans_out;

begin

    sys_rst_n_ibuf : IBUF
        port map (
            O => pcie_sys_rst_n_i,
            I => pcie_sys_rst_n
            );

    osc_clk_ibuf : IBUFDS
        port map(
            i  => osc_clk_p,
            ib => osc_clk_n,
            o  => clk_osc
            );

    --  DCM clock generation for internal bus, ethernet
    clocks : entity work.clocks_usp_serdes
        generic map (
            CLK_FR_FREQ => 300.0
            )
        port map (
            clki_fr       => clk_osc,
            clki_125      => axi_ms.aclk,
            clko_ipb      => clk_ipb_i,
            clko_aux      => clk_aux,
            eth_locked    => pcie_user_lnk_up,
            locked        => clk_locked,
            nuke          => nuke,
            soft_rst      => soft_rst,
            rsto_125      => rst125,
            rsto_ipb      => rst_ipb,
            rsto_aux      => rst_aux,
            rsto_eth      => rst_axi,
            rsto_ipb_ctrl => rst_ipb_ctrl,
            onehz         => onehz
            );

    clk_ipb   <= clk_ipb_i;
    clk_ipb_o <= clk_ipb_i;
    rst_ipb_o <= rst_ipb;
    clk_aux_o <= clk_aux;
    rst_aux_o <= rst_aux;
    locked    <= clk_locked and pcie_user_lnk_up;

    -- TODO: Add equivalent of 'stretched' "pkt" signal from ku105 design
    leds <= '0' & (locked and onehz);


    dma : entity work.pcie_xdma_axi_usp_if
        port map (
            pcie_sys_clk_p => pcie_sys_clk_p,
            pcie_sys_clk_n => pcie_sys_clk_n,
            pcie_sys_rst_n => pcie_sys_rst_n_i,

            pcie_tx_p => pcie_tx_p,
            pcie_tx_n => pcie_tx_n,
            pcie_rx_p => pcie_rx_p,
            pcie_rx_n => pcie_rx_n,

            pcie_user_lnk_up => pcie_user_lnk_up,

            axi_ms => axi_ms,
            axi_sm => axi_sm,

            pcie_int_event0 => ipb_pkt_done
            );


    ipbus_transport_axi : entity work.ipbus_transport_axi_if
        port map (
            ipb_clk => clk_ipb,
            rst_ipb => rst_ipb_ctrl,
            axi_in  => axi_ms,
            axi_out => axi_sm,

            pkt_done => ipb_pkt_done,

            ipb_trans_rx => trans_in,
            ipb_trans_tx => trans_out
            );


    ipbus_transactor : entity work.transactor
        port map (
            clk            => clk_ipb,
            rst            => rst_ipb_ctrl,
            ipb_out        => ipb_out,
            ipb_in         => ipb_in,
            ipb_req        => open,
            ipb_grant      => '1',
            trans_in       => trans_in,
            trans_out      => trans_out,
            cfg_vector_in  => (others => '0'),
            cfg_vector_out => open
            );

end rtl;
