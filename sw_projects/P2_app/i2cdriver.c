/* Copyright (C)
* 2024 - Laurence Barker G8NJJ
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
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <linux/i2c-dev.h>
#include <i2c/smbus.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <stdint.h>

#include "i2cdriver.h"
extern int i2c_fd;                                  // file reference


//
// 8 bit write
//
int i2c_write_byte_data(uint8_t reg, uint8_t data) 
{
  int rc;

  if ((rc = i2c_smbus_write_byte_data(i2c_fd, reg, data & 0xFF)) < 0) 
  {
    printf("%s: write i2c failed: addr=%02X\n", __FUNCTION__, reg);
  }

  return rc;
}

//
// 16 bit write
//
int i2c_write_word_data(uint8_t reg, uint16_t data)
{
  int rc;

  if ((rc = i2c_smbus_write_word_data(i2c_fd, reg, data & 0xFFFF)) < 0) 
  {
    printf("%s: 16 bit write i2c failed: addr=%02X\n", __FUNCTION__, reg);
  }

  return rc;
}



//
// 8 bit read
//
uint8_t i2c_read_byte_data(uint8_t reg, bool *error) 
{
  int32_t data;

  *error = false;
  data = i2c_smbus_read_byte_data(i2c_fd, reg);
  if(data < 0)
  {
    *error = true;
    printf("error on i2c byte read, code=%d\n", data);
  }
  return (uint8_t) (data & 0xFF);
}


//
// 16 bit read 
//
uint16_t i2c_read_word_data(uint8_t reg, bool *error) 
{
  int32_t data;


  *error = false;
  data = i2c_smbus_read_word_data(i2c_fd, reg);
  if(data < 0)
  {
    *error = true;
    printf("error on i2c word read, code=%d\n", data);
  }
  return (uint16_t) (data & 0xFFFF);
}
