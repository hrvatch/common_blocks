clear -all
jasper_scoreboard_3 -init
analyze -sv12 $env(SYNC_FIFO_PATH)/rtl/sync_fifo_with_threshold.sv $env(SYNC_FIFO_PATH)/formal/src/sync_fifo_with_threshold_formal_tb.sv
elaborate -top sync_fifo_with_threshold_formal_tb
clock clk 
reset !rst_n
