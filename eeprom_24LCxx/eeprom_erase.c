// Microchip I2C EEPROM 24LC32/64/128/256/512 一部消去プログラム
// for Raspberry Pi

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <linux/i2c-dev.h>
#include <fcntl.h>
#include <sys/ioctl.h>

#define I2C_ADDR 0x51

int main(int argc, char **argv){
    printf("Microchip I2C EEPROM 24LC32/64/../512 erase program\n usage : %s start_addr bytes padding_num\n", argv[0]);

    int i2c;    // i2cデバイスのファイルディスクリプタ
    int start_addr = 0;     // 開始アドレス
    int erase_bytes = 1;    // 上書きバイト数
    unsigned int padding = 0;        // 上書きする文字
    
    if(argc == 4){
        start_addr = atoi(argv[1]);
        erase_bytes = atoi(argv[2]);
        padding = atoi(argv[3]);
    }
    else{
        printf("error:parameter is few or more\n");
        exit(1);
    }
    // 64kbit = 64*1024/8 = 8192 Bytes
    if(start_addr < 0 || 8192 <= start_addr) start_addr = 0;
    if(start_addr + erase_bytes < 0 || 8192 <= start_addr + erase_bytes) erase_bytes = 1;
    padding &= 0xff;

    // I2CポートをRead/Write属性でオープン
    if ((i2c = open("/dev/i2c-1", O_RDWR)) < 0){
        printf("error:open i2c device /dev/i2c-1\n");
        exit(1);
    }
    if (ioctl(i2c, I2C_SLAVE, (int)I2C_ADDR) < 0){
        printf("error:connect i2c address %02X\n", (int)I2C_ADDR);
        exit(1);
    }
    printf("open success:i2c device /dev/i2c-1, address %02X\n", (int)I2C_ADDR);

    unsigned char buf[3];   // I2C 通信バッファ
    int i;

    // 先頭行 凡例カラム表示
    printf("addr | data\n-----------\n");

    // EEPROM書き込み
    for(i=start_addr; i<start_addr + erase_bytes; i++){
        usleep(10*1000); // 1Bytes書き込みは最悪条件で5.3ミリ秒掛かるため, 10ミリ秒待つ
        
        buf[0] = i >> 8;     // memory addr Hi
        buf[1] = i && 0xff;     // memory ddr low
        buf[2] = padding;
        if (write(i2c, buf, 3) != 3){
            printf("\nerror:send address 2Bytes %02X %02X, padding %02X\n", buf[0], buf[1], buf[2]);
            exit(1);
        }
        
        printf("%04X | %02X (%02X %02X)\n", i, buf[2],buf[0],buf[1]);
    }
    close(i2c);

    exit(0);
}
