//
// register definitions for Xilinx I2C IP core
// Laurence Barker July 2022
// modified from Xilinx xiic_l.h
//



//
// Register offsets for the XIic device.
//
#define XIIC_DGIER_OFFSET	0x1C  /**< Global Interrupt Enable Register */
#define XIIC_IISR_OFFSET	0x20  /**< Interrupt Status Register */
#define XIIC_IIER_OFFSET	0x28  /**< Interrupt Enable Register */
#define XIIC_RESETR_OFFSET	0x40  /**< Reset Register */
#define XIIC_CR_REG_OFFSET	0x100 /**< Control Register */
#define XIIC_SR_REG_OFFSET	0x104 /**< Status Register */
#define XIIC_DTR_REG_OFFSET	0x108 /**< Data Tx Register */
#define XIIC_DRR_REG_OFFSET	0x10C /**< Data Rx Register */
#define XIIC_ADR_REG_OFFSET	0x110 /**< Address Register */
#define XIIC_TFO_REG_OFFSET	0x114 /**< Tx FIFO Occupancy */
#define XIIC_RFO_REG_OFFSET	0x118 /**< Rx FIFO Occupancy */
#define XIIC_TBA_REG_OFFSET	0x11C /**< 10 Bit Address reg */
#define XIIC_RFD_REG_OFFSET	0x120 /**< Rx FIFO Depth reg */
#define XIIC_GPO_REG_OFFSET	0x124 /**< Output Register */


//
// Reset Register mask
//
#define XIIC_RESET_MASK		0x0000000A /**< RESET Mask  */


// Control Register masks (CR) mask(s)
//
#define XIIC_CR_ENABLE_DEVICE_MASK	0x00000001 /**< Device enable = 1 */
#define XIIC_CR_TX_FIFO_RESET_MASK	0x00000002 /**< Transmit FIFO reset=1 */
#define XIIC_CR_MSMS_MASK		0x00000004 /**< Master starts Txing=1 */
#define XIIC_CR_DIR_IS_TX_MASK		0x00000008 /**< Dir of Tx. Txing=1 */
#define XIIC_CR_NO_ACK_MASK		0x00000010 /**< Tx Ack. NO ack = 1 */
#define XIIC_CR_REPEATED_START_MASK	0x00000020 /**< Repeated start = 1 */
#define XIIC_CR_GENERAL_CALL_MASK	0x00000040 /**< Gen Call enabled = 1 */

//
// Status Register masks (SR) mask(s)
//
#define XIIC_SR_GEN_CALL_MASK		0x00000001 /**< 1 = A Master issued a GC */
#define XIIC_SR_ADDR_AS_SLAVE_MASK	0x00000002 /**< 1 = When addressed as * slave */
#define XIIC_SR_BUS_BUSY_MASK		0x00000004 /**< 1 = Bus is busy */
#define XIIC_SR_MSTR_RDING_SLAVE_MASK	0x00000008 /**< 1 = Dir: Master <--* slave */
#define XIIC_SR_TX_FIFO_FULL_MASK	0x00000010 /**< 1 = Tx FIFO full */
#define XIIC_SR_RX_FIFO_FULL_MASK	0x00000020 /**< 1 = Rx FIFO full */
#define XIIC_SR_RX_FIFO_EMPTY_MASK	0x00000040 /**< 1 = Rx FIFO empty */
#define XIIC_SR_TX_FIFO_EMPTY_MASK	0x00000080 /**< 1 = Tx FIFO empty */

//
// Data Tx Register (DTR) mask(s)
//
#define XIIC_TX_DYN_START_MASK		0x00000100 /**< 1 = Set dynamic start */
#define XIIC_TX_DYN_STOP_MASK		0x00000200 /**< 1 = Set dynamic stop */
#define IIC_TX_FIFO_DEPTH		16     /**< Tx fifo capacity */


//
// Data Rx Register (DRR) mask(s)
//
#define IIC_RX_FIFO_DEPTH		16	/**< Rx fifo capacity */


#define XIIC_TX_ADDR_SENT		0x00
#define XIIC_TX_ADDR_MSTR_RECV_MASK	0x02


//
// The following constants are used to specify whether to do
// Read or a Write operation on IIC bus.
//
#define XIIC_READ_OPERATION	1 /**< Read operation on the IIC bus */
#define XIIC_WRITE_OPERATION	0 /**< Write operation on the IIC bus */


//
// The following constants are used with the transmit FIFO fill function to
// specify the role which the IIC device is acting as, a master or a slave.
//
#define XIIC_MASTER_ROLE	1 /**< Master on the IIC bus */
#define XIIC_SLAVE_ROLE		0 /**< Slave on the IIC bus */


//
// The following constants are used with Transmit Function (XIic_Send) to
// specify whether to STOP after the current transfer of data or own the bus
// with a Repeated start.
//
#define XIIC_STOP		0x00 /**< Send a stop on the IIC bus after the current data transfer */
#define XIIC_REPEATED_START	0x01 /**< Donot Send a stop on the IIC bus after the current data transfer */



//
// Device Global Interrupt Enable Register masks (CR) mask(s)
//
#define XIIC_GINTR_ENABLE_MASK	0x80000000 /**< Global Interrupt Enable Mask */

//
// IIC Device Interrupt Status/Enable (INTR) Register Masks
//
//Interrupt Status Register (IISR)
// This register holds the interrupt status flags for the Spi device.
//
//Interrupt Enable Register (IIER)
//
// This register is used to enable interrupt sources for the IIC device.
// Writing a '1' to a bit in this register enables the corresponding Interrupt.
// Writing a '0' to a bit in this register disables the corresponding Interrupt.
//
// IISR/IIER registers have the same bit definitions and are only defined once.
//
#define XIIC_INTR_ARB_LOST_MASK	0x00000001 /**< 1 = Arbitration lost */
#define XIIC_INTR_TX_ERROR_MASK	0x00000002 /**< 1 = Tx error/msg complete */
#define XIIC_INTR_TX_EMPTY_MASK	0x00000004 /**< 1 = Tx FIFO/reg empty */
#define XIIC_INTR_RX_FULL_MASK	0x00000008 /**< 1 = Rx FIFO/reg=OCY level */
#define XIIC_INTR_BNB_MASK	0x00000010 /**< 1 = Bus not busy */
#define XIIC_INTR_AAS_MASK	0x00000020 /**< 1 = When addr as slave */
#define XIIC_INTR_NAAS_MASK	0x00000040 /**< 1 = Not addr as slave */
#define XIIC_INTR_TX_HALF_MASK	0x00000080 /**< 1 = Tx FIFO half empty */


//
// status values
//
#define XST_SUCCESS 0L
#define XST_FAILURE 1L