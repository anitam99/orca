#include "ORCAEN965Readout.hh"
#include <errno.h>

#define ShiftAndExtract(aValue,aShift,aMask) (((aValue)>>(aShift)) & (aMask))

bool ORCaen965Readout::Readout(SBC_LAM_Data* lamData)
{
	uint32_t dataId               = GetHardwareMask()[0];
	uint32_t locationMask         = ((GetCrate() & 0x01e)<<21) | 
                                    ((GetSlot() & 0x0000001f)<<16);
	uint32_t firstStatusRegOffset = GetDeviceSpecificData()[0];
 	uint32_t dataBufferOffset     = GetDeviceSpecificData()[1];

	ensureDataCanHold(4 * 2); //max this card can produce

	for(uint32_t chan=0;chan<4;chan++){
		if(enabledMask & (1<<chan)){
			uint16_t theStatusReg;
            int32_t result = VMERead(GetBaseAddress()+firstStatusRegOffset+(chan*4),
                                     0x39,
                                     sizeof(theStatusReg),
                                     theStatusReg);
			if(result == sizeof(theStatusReg) && (theStatusReg&0x8000)){
				uint16_t aValue;
                result = VMERead(GetBaseAddress()+firstAdcRegOffset+(chan*4),
                                 0x39,
                                 sizeof(aValue),
                                 aValue);
				if(result == sizeof(aValue)){
					if(((dataId) & 0x80000000)){ //short form
						data[dataIndex++] = dataId | locationMask | 
                            ((chan & 0x0000000f) << 12) | (aValue & 0x0fff);
					} 
					else { //long form
						data[dataIndex++] = dataId | 2;
						data[dataIndex++] = locationMask | 
                            ((chan & 0x0000000f) << 12) | (aValue & 0x0fff);
					}
				} 
				else if (result < 0) {
                    LogBusError("Rd Err: CAEN 965 0x%04x %s",
                        GetBaseAddress(),strerror(errno));                
                }
			} 
			else if (result < 0) {
                LogBusError("Rd Err: CAEN 965 0x%04x %s",
                    GetBaseAddress(),strerror(errno));   
            }
		}
	}
	
	//////
	uint16_t theStatusReg;
	int32_t result = VMERead(GetBaseAddress()+firstStatusRegOffset,
							 0x39,
							 sizeof(theStatusReg),
							 theStatusReg);
	
	if((result == sizeof(theStatusReg)) && (theStatusReg & 0x0001)){
		//OK, at least one data value is ready, first value read should be a header
		int32_t dataValue;
		result = VMERead(GetBaseAddress()+dataBufferOffset, 0x39, sizeof(dataValue), dataValue);
		uint8_t validData = YES; //assume OK until shown otherwise
		if((result == sizeof(dataValue)) && (ShiftAndExtract(dataValue,24,0x7) == 0x2)){
			int32_t numMemorizedChannels = ShiftAndExtract(dataValue,8,0x3f);
			int32_t i;
			if((numMemorizedChannels>0)){
				//make sure the data buffer can hold our data. Note that we do NOT ship the end of block. 
				ensureDataCanHold(numMemorizedChannels + 2);
				
				int32_t savedDataIndex = dataIndex;
				data[dataIndex++] = dataId | (numMemorizedChannels + 2);
				data[dataIndex++] = locationMask;
				
				for(i=0;i<numMemorizedChannels;i++){
					result = VMERead(GetBaseAddress()+dataBufferOffset, 0x39, sizeof(dataValue), dataValue);
					if((result == sizeof(dataValue)) && (ShiftAndExtract(dataValue,24,0x7) == 0x0))data[dataIndex++] = dataValue;
					else break;
				}
				
				//OK we read the data, get the end of block
				result = VMERead(GetBaseAddress()+dataBufferOffset, 0x39, sizeof(dataValue), dataValue);
				if((result != sizeof(dataValue)) || (ShiftAndExtract(dataValue,24,0x7) != 0x4)){
					//some kind of bad error, report and flush the buffer
					LogBusError("Rd Err: CAEN 965 0x%04x %s", GetBaseAddress(),strerror(errno)); 
					dataIndex = savedDataIndex;
					flushDataBuffer();
				}
			}
		}
	}
	
    return true; 
}

void flushDataBuffer()
{
	uint32_t dataBufferOffset     = GetDeviceSpecificData()[1];
	//flush the buffer, read until not valid datum
	int i;
	for(i=0;i<0x07FC;i++) {
		unsigned long dataValue;
		[controller readLongBlock:&dataValue
						atAddress:dataBufferAddress
						numToRead:1
					   withAddMod:[self addressModifier]
					usingAddSpace:0x01];
		if(ShiftAndExtract(dataValue,24,0x7) == 0x6) break;
	}
}
