.PHONY: jg_sync_fifo_with_threshold jg_sync_fifo_with_clear

jg_sync_fifo_with_threshold:
	jg $(SYNC_FIFO_PATH)/formal/tcl/sync_fifo_with_threshold.tcl

jg_sync_fifo_with_clear:
	jg $(SYNC_FIFO_PATH)/formal/tcl/sync_fifo_with_clear.tcl

clean:
	rm -rf jgproject

help:
	@echo "Available targets:"
	@echo "  jg_sync_fifo_with_threshold         - Start Jasper FPV for Sync FIFO with threshold"
	@echo "  jg_sync_fifo_with_clear             - Start Jasper FPV for Sync FIFO with clear"
	@echo "  clean															 - Remove simulation artefacts"
