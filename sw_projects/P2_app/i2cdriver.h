/* Copyright (C)
 2024 - Laurence Barker G8NJJ
*
*   This program is free software: you can redistribute it and/or modify
*   it under the terms of the GNU General Public License as published by
*   the Free Software Foundation, either version 3 of the License, or
*   (at your option) any later version.
*
*   This program is distributed in the hope that it will be useful,
*   but WITHOUT ANY WARRANTY; without even the implied warranty of
*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*   GNU General Public License for more details.
*
*   You should have received a copy of the GNU General Public License
*   along with this program.  If not, see <https://www.gnu.org/licenses/>.
*
*/


#ifndef __i2cdriver_h
#define __i2cdriver_h

#include <stdint.h>
#include <stdbool.h>


//
// 8 bit write
//
int i2c_write_byte_data(uint8_t reg, uint8_t data); 

//
// 16 bit write
//
int i2c_write_word_data(uint8_t reg, uint16_t data); 

//
// 8 bit read
//
uint8_t i2c_read_byte_data(uint8_t reg, bool *error); 

//
// 16 bit read 
//
uint16_t i2c_read_word_data(uint8_t reg, bool *error); 



#endif  //#ifndef
