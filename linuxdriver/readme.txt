These files include two patches to enable operation on a 32 bit or 64 bit RaspberryPi4 Compute Module:


1. function "bridge_mmap (cdev_ctrl.c, line 195): 4 variables to become 64 bits

int bridge_mmap(struct file *file, struct vm_area_struct *vma)
{
struct xdma_dev *xdev;
struct xdma_cdev *xcdev = (struct xdma_cdev *)file->private_data;
uint64_t off;// LVB 21/2/2021: must be 64 bit
uint64_t phys;// LVB 21/2/2021: must be 64 bit
uint64_t vsize;// LVB 21/2/2021: must be 64 bit
uint64_t psize;// LVB 21/2/2021: must be 64 bit



2. function set_dma_mask (libxdma.c, line 3881): needs to use 64 bit version for pci_set_consistent_dma_mask()

static int set_dma_mask(struct pci_dev *pdev)
{
	if (!pdev) {
		pr_err("Invalid pdev\n");
		return -EINVAL;
	}

	dbg_init("sizeof(dma_addr_t) == %ld\n", sizeof(dma_addr_t));
	/* 64-bit addressing capability for XDMA? */
	if (!pci_set_dma_mask(pdev, DMA_BIT_MASK(64))) {
		/* query for DMA transfer */
		/* @see Documentation/DMA-mapping.txt */
		dbg_init("pci_set_dma_mask()\n");
		/* use 64-bit DMA */
		dbg_init("Using a 64-bit DMA mask.\n");
		/* use 32-bit DMA for descriptors */
		pci_set_consistent_dma_mask(pdev, DMA_BIT_MASK(64));
		/* use 64-bit DMA, 32-bit for consistent */
	} else if (!pci_set_dma_mask(pdev, DMA_BIT_MASK(32))) {
		dbg_init("Could not set 64-bit DMA mask.\n");
		pci_set_consistent_dma_mask(pdev, DMA_BIT_MASK(32));
		/* use 32-bit DMA */
		dbg_init("Using a 32-bit DMA mask.\n");
	} else {
		dbg_init("No suitable DMA possible.\n");
		return -EINVAL;
	}

	return 0;
}


also changes were needed to cdev_xdma.c and libxdma.c to handle changes
to the linux kernel introduced at V5.18. See:

https://community.element14.com/technologies/fpga-group/b/blog/posts/installing-xilinx-vivado-on-ubuntu
(The Xilinx distribution as at April 2023 has not been edited to include this!)
The driver suitable for pre-kernel 5.18 is in folder xdma_pre_kernel_5.18

Thank you to Rick Koch N1GP for improving my fix!



The files in this directory provide Xilinx PCIe DMA drivers, example software,
and example test scripts that can be used to exercise the Xilinx PCIe DMA IP.

This software can be used directly or referenced to create drivers and software
for your Xilinx FPGA hardware design.

Directory and file description:
===============================
 - xdma/: This directory contains the Xilinx PCIe DMA kernel module
       driver files.

 - xdma_pre_kernel_5.18/: This directory contains the Xilinx PCIe DMA kernel module
       driver files for earlier OS releases

 - include/: This directory contains all include files that are needed for
	compiling driver.

 - tests/: This directory contains example application software to exercise the
	provided kernel module driver and Xilinx PCIe DMA IP. This directory
	also contains the following scripts and directories.

	 - load_driver.sh:
		This script loads the kernel module and creates the necissary
		kernel nodes used by the provided software.
		The The kernel device nodes will be created under /dev/xdma*.
		Additional device nodes are created under /dev/xdma/card* to
		more easily differentiate between multiple PCIe DMA enabled
		cards. Root permissions will be required to run this script.

	 - run_test.sh:
		This script runs sample tests on a Xilinx PCIe DMA target and
		returns a pass (0) or fail (1) result.
		This script is intended for use with the PCIe DMA example
		design.

	 - perform_hwcount.sh:
		This script runs hardware performance for XDMA for both Host to
		Card (H2C) and Card to Host (C2H). The result are copied to
		'hw_log_h2c.txt' and hw_log_c2h.txt' text files. 
		For each direction the performance script loops from 64 bytes
		to 4MBytes and generate performance numbers (byte size doubles
		for each loop count).
		You can grep for 'data rate' on those two files to see data
		rate values.
		Data rate values are in percentage of maximum throughput.
		Maximum data rate for x8 Gen3 is 8Gbytes/s, so for a x8Gen3
		design value of 0.81 data rate is 0.81*8 = 6.48Gbytes/s.
		Maximum data rate for x16 Gen3 is 16Gbytes/s, so for a x16Gen3
		design value of 0.78 data rate is 0.78*16 = 12.48Gbytes/s.
		This program can be run on AXI-MM example design.
		AXI-ST example design is a loopback design, both H2C and C2H
		are connected. Running on AXI-ST example design will not
		generate proper numbers.
		If a AXI-ST design is independent of H2C and C2H, performance
		number can be generated. 
	- data/:
		This directory contains binary data files that are used for DMA
		data transfers to the Xilinx FPGA PCIe endpoint device.

Usage:
  - get the kernel headers so the kernel module can compile: 
    (note if this fails you will need to use an older OS release, or rebuild the kernel 
     by following the instructions at https://www.raspberrypi.org/documentation/linux/kernel/building.md)


        sudo apt install raspberrypi-kernel-headers


  - If you are updating: unload the previous driver from memory.
        sudo rmmod -s xdma
  
  - Change directory to the driver directory.
        cd xdma

  - Compile and install the kernel module driver.
        make
		sudo make install

  - Load the kernel module driver:
	sudo modprobe xdma

  - Change directory to the tools directory.
        cd tools
  
  - Compile the provided example test tools.
        make
	
  - test the new driver.
	cd tests
        ./load_driver.sh
  - Run the provided test script to generate basic DMA traffic.
        ./run_test.sh
  - Check driver Version number
        modinfo xdma (or)
        modinfo ../xdma/xdma.ko    

Updates and Backward Compaitiblity:
  - The following features were added to the PCIe DMA IP and driver in Vivado
    2016.1. These features cannot be used with PCIe DMA IP if the IP was
    generated using a Vivado build earlier than 2016.1.
      - Poll Mode: Earlier versions of Vivado only support interrupt mode which
	is the default behavior of the driver.
      - Source/Destination Address: Earlier versions of Vivado PCIe DMA IP
	required the low-order bits of the Source and Destination address to be
	the same.
	As of 2016.1 this restriction has been removed and the Source and
	Destination addresses can be any arbitrary address that is valid for
        your system.

Frequently asked questions:
  Q: How do I uninstall the kernel module driver?
  A: Use the following commands to uninstall the driver.
       - Uninstall the kernel module.
             rmmod -s xdma

  Q: How do I modify the PCIe Device IDs recognized by the kernel module driver?
  A: The xdma/xdma_mod.c file constains the pci_device_id struct that identifies
     the PCIe Device IDs that are recognized by the driver in the following
     format:
         { PCI_DEVICE(0x10ee, 0x8038), },
     Add, remove, or modify the PCIe Device IDs in this struct as desired. Then
     uninstall the existing xdma kernel module, compile the driver again, and
     re-install the driver using the load_driver.sh script.

  Q: By default the driver uses interupts to signal when DMA transfers are
     completed. How do I modify the driver to use polling rather than
     interrupts to determine when DMA transactions are completed?
  A: The driver can be changed from being interrupt driven (default) to being
     polling driven (poll mode) when the kernel module is inserted. To do this
     modify the load_driver.sh file as follows:
        Change: insmod xdma/xdma.ko
        To:     insmod xdma/xdma.ko poll_mode=1
     Note: Interrupt vs Poll mode will apply to all DMA channels. If desired the
     driver can be modified such that some channels are interrupt driven while
     others are polling driven. Refer to the poll mode section of PG195 for
     additional information on using the PCIe DMA IP in poll mode. 
