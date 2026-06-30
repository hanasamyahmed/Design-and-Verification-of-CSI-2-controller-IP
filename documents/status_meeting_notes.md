# Status Meeting Notes
## 10-2-2026
### 1- At the Initialization stage , the Processor need to check if CSI-2 RX supports Disabled CRC
### 2- IN RX, if Header Data already Known, Why ECC is Implemented then?  
### 3- How are Request and Ready signals (D-PHY) handled?
### 4- I2C Micro-architecture/FSM

## 2-4-2026
### 1- Block diagram for testbench explaining how the tx_mem and rx_mem interact with the DUT and How the DUT is driven by the testbench
### 2- Block diagram dor Dphy explaining how the behavioral dphy implemented works 
### 3-Do we need to wait a couple byte clock cycles for d phy to shut down? is it a requirement that need to be applied in order for the controller to work properly? if so, then how many clock cycles exactly?
### 4- Revise the constraints of each block (example: are these signals really quasistatic or they are written like this in order to pass spyglass?)
### 5-Check resets(are they all Asynchronous? if no then a proper explanation of why this reset is not asynchronous should be provided)
### 6-Read about reset synchronizers and why do we need them to synchronize the three resets included in our system.


## 10-4-2026
### 1-use reset synchronizers
### 2- make the testbench stop when an error is spotted
### 3-resolve the I2C two sda wires into one inout wire
### 4-check why the fifos are the problem in the slack calculated during synthesis
### 5-in constraints file, line 60, why set_case_analysis is used?


## 13-5-2026
### 1-Add an Agenda
### 2- Modify the Intro to include (how does the image sensor work, what is an image,frame,line,pixels,...etc)
### 3- what is a bus interface ,what are the bus interfaces we use briefly
### 4- why APB not AHB and why APB and I2C
### 5-mention how the system is configured (initialized)
### 6- after ecc operation , mention where is the ecc in the packet and explain how to generate it for the whole 26 bits
### 7-before the discussion, prepare a folder with simulation results for each block and a running simulation
### 8-add block diagrams 
### 9- add scrambler details (operation ) with visual aids
### 10- explain APB more in slides
### 11- why is CRC optional
### 12- look up the power gating and clock gating concepts
### 13- Investigate hold constraints
### 14 - add all groups reports (after synthesis) and understand each line in them
### 15- remove the pixel reset( make the byte reset synchronized with both pixel and byte clk)
### 16- Add at least three points future work


