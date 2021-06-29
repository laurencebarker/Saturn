#!/bin/bash

transferSize=$1
transferCount=$2
h2cChannels=$3
c2hChannels=$4

tool_path=../xdmatools

testError=0
# Run the PCIe DMA memory mapped write read test
echo "Info: Running PCIe DMA memory mapped write read test"
echo "      transfer size:  $transferSize"
echo "      transfer count: $transferCount"

# Write to all enabled h2cChannels in parallel
if [ $h2cChannels -gt 0 ]; then
    addrOffset=0x10000
    curChannel=0
    echo "Info: Writing $transferSize bytes to h2c channel $curChannel at address offset $addrOffset."
    $tool_path/dma_to_device -d /dev/xdma0_h2c_0 -f data/datafile0_8K.bin -v -s $transferSize -a $addrOffset -c $transferCount &
    # If all channels have active transactions we must wait for them to complete
fi

# Wait for the last transaction to complete.
wait

echo "reading FIFO reported depth after write"
../xdmatools/userio_rw /dev/xdma0_user 0x900c

# Read from all enabled c2hChannels in parallel
if [ $c2hChannels -gt 0 ]; then
    addrOffset=0x10000
    curChannel=0
    rm -f data/output_datafile0_8K.bin
    echo "Info: Reading $transferSize bytes from c2h channel $curChannel at address offset $addrOffset."
    $tool_path/dma_from_device -d /dev/xdma0_c2h_0 -f data/output_datafile0_8K.bin -v -s $transferSize -a $addrOffset -c $transferCount &
fi

# Wait for the last transaction to complete.
wait

echo "reading FIFO reported depth after read"
../xdmatools/userio_rw /dev/xdma0_user 0x900c


# Verify that the written data matches the read data if possible.
if [ $h2cChannels -eq 0 ]; then
  echo "Info: No data verification was performed because no h2c channels are enabled."
elif [ $c2hChannels -eq 0 ]; then
  echo "Info: No data verification was performed because no c2h channels are enabled."
else
  echo "Info: Checking data integrity."
    cmp data/output_datafile0_8K.bin data/datafile0_8K.bin -n $transferSize
    returnVal=$?
    if [ ! $returnVal == 0 ]; then
      echo "Error: The data written did not match the data that was read."
      echo "       address range:   $(($i*$transferSize)) - $((($i+1)*$transferSize))"
      echo "       write data file: data/datafile${i}_4K.bin"
      echo "       read data file:  data/output_datafile${i}_4K.bin"
      testError=1
    else
      echo "Info: Data check passed for address range ($transferSize) - ($transferSize)."
    fi
fi

# Exit with an error code if an error was found during testing
if [ $testError -eq 1 ]; then
  echo "Error: Test completed with Errors."
  exit 1
fi

# Report all tests passed and exit
echo "Info: All PCIe DMA memory mapped tests passed."
exit 0
