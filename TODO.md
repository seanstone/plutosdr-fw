* pluto: load bitstream in fsbl
* ADRV9364: LED and GPIO
* ADRV9364: motd
* Generate mass storage vfat.img dynamically
* Generate vdma test client node in dts:
```
    vdmatest_1: vdmatest@1 {
               compatible ="xlnx,axi-vdma-test-1.00.a";
               xlnx,num-fstores = <0x1>;
               dmas = <&axi_dma_0 0
                       &axi_dma_0 1>;
               dma-names = "vdma0", "vdma1";
        };
```
Also should fix `xlnx,device-id`:
```
dma-channel@42000030 {
				compatible = "xlnx,axi-dma-s2mm-channel";
				dma-channels = <0x1>;
				interrupts = <0 30 4>;
				xlnx,datawidth = <0x20>;
				xlnx,device-id = <0x1>;
			};
```
* Fix dependency chain in Makefile (ip etc.)
* Configure IP in system_bd
* Use AXI interrupt controller
* Add microblaze etc.
* GNURadio integration
* Use https://github.com/bperez77/xilinx_axidma to test vdma
* Add a video encoder