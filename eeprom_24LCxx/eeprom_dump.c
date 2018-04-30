// Microchip I2C EEPROM 24LC32/64/128/256/512 ダンプ出力プログラム
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
    printf("Microchip I2C EEPROM 24LC32/64/../512 dump program\n usage : %s [start_addr lines]\n", argv[0]);

    int i2c;    // i2cデバイスのファイルディスクリプタ
    int start_addr = 0;     // 開始行（16Bytes毎の行数）
    int disp_lines = 5;     // 表示行数（16Bytesで1行）
    
    if(argc == 3){
        start_addr = atoi(argv[1]);
        disp_lines = atoi(argv[2]);
    }
    // 64kbit = 64*1024/8 = 8192 Bytes → 8192/16 = 512 表示行
    if(start_addr < 0 || 512 < start_addr) start_addr = 0;
    if(start_addr + disp_lines < 0 || 512 < start_addr + disp_lines) disp_lines = 0;
    
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
    int i, j;

    // ダンプ先頭行 カラム番号表示
    printf("        ");
    for(j=0; j<0x10; j++) printf("%02X ", j);
    printf("\n        ");
    for(j=0; j<0x10; j++) printf("---");
    printf("\n");

    // EEPROM内容をダンプ出力する
    for(i=start_addr; i<start_addr + disp_lines; i++){
        printf("%04X  | ", i*16);
        for(j=0; j<0x10; j++){
            usleep(10*1000); // 1Bytes書き込みは最悪条件で5.3ミリ秒掛かるため, 10ミリ秒待つ
            //読み出しアドレス（32kbit〜512kbitは2Bytesアドレス
            buf[0] = (i * 0x10 + j) >>8;                 // memory addr Hi
            buf[1] = (i * 0x10 + j) & 0xff;      // memory ddr low
            if (write(i2c, buf, 2) != 2){
                printf("\nerror:send address 2Bytes %02X %02X\n", buf[0], buf[1]);
                exit(1);
            }
            // アドレス送信後、1Bytes読みだす
            if (read(i2c, &buf, 1) != 1) {
                printf("\nerror:read data\n");
                exit(1);
            }
            // 受信データ 1Byteを表示する
            printf("%02X ", buf[0]);
        }
        printf("\n");
    }
    printf("\n");
    close(i2c);
    
    exit(0);
}
