#!/usr/bin/env python3

import sys
import serial
import time

if len(sys.argv) == 1:
  sys.exit('No filename given to send')

if len(sys.argv) == 2:
  serialport = '/dev/ttyUSB0'

if len(sys.argv) == 3:
  serialport = sys.argv[2]

print(f'Sending {sys.argv[1]}')
print(f'Using port {serialport}')

f = open(sys.argv[1], "rb")

startAddress = 0x0205
content = f.read()
checkError = False
blockSize = 10

with serial.Serial(serialport) as ser: ## 9600,8,N,1
  print('Opening serial port...')
  time.sleep(3)
  print('Writing file to serial port')
  blockIndex = 0
  blockBytesRemaining = len(content)
  while (blockBytesRemaining > 0) and (not checkError):
    blockSize = min(blockBytesRemaining, blockSize)
    header = f'0x{(startAddress + blockIndex):04x}'
    print(header, end="")
    for byte in header:
        ser.write(str(byte).encode('ascii'))
    checka = 1
    checkb = 0
    for i in range(blockSize):
      data = content[blockIndex]
      blockIndex = blockIndex + 1
      checka = (checka + data) % 256
      checkb = (checkb + checka) % 256
      block = f' {data:02X}'
      blockBytesRemaining = blockBytesRemaining - 1
      print(block, end="")
      for byte in block:
        ser.write(str(byte).encode('ascii'))
    checksum = f'{((checka << 8) | checkb):0X}'
    ser.write(b'\r')
    ret = ser.readline()
    ret = ret.strip()
    if not ret.endswith(bytes(checksum, 'ascii')):
      print(' -- recv error')
      checkError = True
    else:
      print(' -- recv ok')
  ser.write(b'\r')
  if checkError:
    print("Upload error - mismatched checksum")

  f.close()
