/*
 * 
 * BOSCH BMP085 - Digital pressure sensor Library
 * for Raspberry Pi
 * 
 * (C)opyright INOUE Hirokazu
 * 2018 May 19
 * License: CC BY-SA v3.0 - http://creativecommons.org/licenses/by-sa/3.0/
 * 
 * compile : gcc bmp085_debug.c -lwiringPi
 * 
*/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <linux/i2c-dev.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <math.h>

//#define WIRING_PI

#ifdef WIRING_PI
#include <wiringPi.h>
#endif

#define BMP085_I2C_ADDRESS 0x77
// IMPORTANT ! : Rpi BCM_GPIO = 4  is equivalent to WiringPi GPIO = 7
#define GPIO_WRITE_PIN 7

const unsigned char BMP085_OVERSAMPLING_SETTING = 3;

// デバッグ時に1とすることで、計算途中の変数を端末に表示する
const int debug_info = 1;

/*
 * I2C デバイス EEPROM レジスタ i2c_reg よりint値を読み込む
 * (データ形式はビッグエンディアン）
 */
int i2c_read_int(int file, unsigned char i2c_reg)
{
    short int val = 0;

    char buf[1] = { i2c_reg };
    write(file, buf, 1);
    char data[2] = { 0, 0 };
    if(read(file, data, 2) != 2) {
        printf("error : less than 2 bytes data read from I2C device\n");
    }
    else {
        val = ((data[0] << 8) & 0xff00) | data[1];
        if(val & 0x8000) {
            val = -(val ^ 0xffff) + 1;
        }
    }
    if(debug_info) {
        printf("(0x%02X) = 0x%02X, 0x%02X (int %d)\n", i2c_reg, data[0], data[1], val);
    }
    return (val);
}

/*
 * I2C デバイス EEPROM レジスタ i2c_reg よりunsigned int値を読み込む
 * (データ形式はビッグエンディアン）
 */
int i2c_read_unsigned_int(int file, unsigned char i2c_reg)
{
    unsigned int val = 0;

    char buf[1] = { i2c_reg };
    write(file, buf, 1);
    char data[2] = { 0, 0 };
    if(read(file, data, 2) != 2) {
        printf("error : less than 2 bytes data read from I2C device\n");
    }
    else {
        val = ((data[0] << 8) & 0xff00) | data[1];
    }
    if(debug_info) {
        printf("(0x%02X) = 0x%02X, 0x%02X (uint %u)\n", i2c_reg, data[0], data[1], val);
    }
    return (val);
}

/*
 * I2C デバイスにバッファbufよりlengthバイト書き込む
 */
void i2c_write_bytes(int file, char *buf, int length)
{
    write(file, buf, length);
}

/*
 * I2C デバイスのEEPROMレジスタi2c_regより、バッファdataにlengthバイト読み込む
 */
int i2c_read_bytes(int file, unsigned char i2c_reg, char *data, int length)
{
    char buf[1] = { i2c_reg };
    write(file, buf, 1);

    if(read(file, data, length) != length) {
        printf("error : less than %d bytes data read from I2C device\n", length);
        return (0);
    }
    if(debug_info) {
        printf("(0x%02X) = ", i2c_reg);
        for (int i = 0; i < length; i++)
            printf("0x%02X, ", data[i]);
    }
    // 読み込んだデータBytes値を返す
    return (length);
}

int bmp085_calc_temperature(unsigned int ut, short unsigned int ac5, short unsigned int ac6,
                            short int mc, short int md, int *b5)
{
    int t, x1, x2;

    x1 = (int) (((ut - ac6) * ac5) / (1 << 15));
    x2 = (int) ((mc * (1 << 11)) / (x1 + md));
    *b5 = x1 + x2;
    t = (int) ((*b5 + 8) / (1 << 4));
    if(debug_info) {
        printf("x1 = %d, x2 = %d, b5 = %d\n", x1, x2, *b5);
    }

    return (t);
}

int bmp085_calc_pressure(short int ac1, short int ac2, short int ac3, short unsigned int ac4,
                         unsigned int up, short int b1, short int b2, int b5)
{
    int x1, x2, x3, b3;
    unsigned int b4;
    int b6;
    unsigned int b7;
    int p;

    b6 = (int) (b5 - 4000);

    x1 = (int) ((b2 * (b6 * b6 / (1 << 12))) / (1 << 11));
    x2 = (int) ((ac2 * b6) / (1 << 11));
    x3 = x1 + x2;
    b3 = (int) ((((int) ((ac1) * 4 + x3) << BMP085_OVERSAMPLING_SETTING) + 2) / 4);
    if(debug_info)
        printf("x1=%d, x2=%d, x3=%d, b3=%d\n", x1, x2, x3, b3);

    x1 = (int) ((ac3 * b6) / (1 << 13));
    x2 = (int) ((b1 * (b6 * b6 / (1 << 12))) / (1 << 16));
    x3 = (int) (((x1 + x2) + 2) / (1 << 2));
    b4 = (unsigned int) (ac4 * (int) (x3 + 32768) / (1 << 15));
    if(debug_info)
        printf("x1=%d, x2=%d, x3=%d, b4=%u\n", x1, x2, x3, b4);
    if(b4 == 0) {
        if(debug_info)
            printf("error : b4 = 0 (divide 0)\n");
        return (0);
    }

    b7 = (unsigned int) (((int) (up) - b3) * (50000 >> BMP085_OVERSAMPLING_SETTING));
    if(b7 < 0x80000000)
        p = (int) (b7 * 2 / b4);
    else
        p = (int) (b7 / b4 * 2);
    if(debug_info)
        printf("b7=%u, p=%d\n", b7, p);

    x1 = (int) (p / (1 << 8) * p / (1 << 8));
    x1 = (int) ((x1 * 3038) / (1 << 16));
    x2 = (int) ((-7357 * p) / (1 << 16));
    p += (int) ((x1 + x2 + 3791) / (1 << 4));

    if(debug_info)
        printf("x1=%d, x2=%d, p=%d\n", x1, x2, p);

    return (p);
}

void bmp085_getvalue(float *t, float *p)
{
    // GPIO 4 をBMP085の電源として利用する設定
#ifdef WIRING_PI
    if(wiringPiSetup() == -1) {
        printf("error wiringPi setup\n");
        return;
    }
    pinMode(GPIO_WRITE_PIN, OUTPUT);
    digitalWrite(GPIO_WRITE_PIN, HIGH);
#else
    system("gpio -g mode 4 out");
    system("gpio -g write 4 1");
#endif

    usleep(250 * 1000);         // BMP085の電源ON後0.25秒待つ

    // I2Cデバイスを開く
    int file;
    char *bus = "/dev/i2c-1";

    if((file = open(bus, O_RDWR)) < 0) {
        printf("Failed to open the bus. \n");
        exit(1);
    }
    ioctl(file, I2C_SLAVE, BMP085_I2C_ADDRESS);


    if(debug_info)
        printf("ac1 ");
    short int ac1 = i2c_read_int(file, 0xaa);

    if(debug_info)
        printf("ac2 ");
    short int ac2 = i2c_read_int(file, 0xac);

    if(debug_info)
        printf("ac3 ");
    short int ac3 = i2c_read_int(file, 0xae);

    if(debug_info)
        printf("ac4 ");
    short unsigned int ac4 = i2c_read_unsigned_int(file, 0xb0);

    if(debug_info)
        printf("ac5 ");
    short unsigned int ac5 = i2c_read_unsigned_int(file, 0xb2);

    if(debug_info)
        printf("ac6 ");
    short unsigned int ac6 = i2c_read_unsigned_int(file, 0xb4);

    if(debug_info)
        printf("b1 ");
    short int b1 = i2c_read_int(file, 0xb6);

    if(debug_info)
        printf("b2 ");
    short int b2 = i2c_read_int(file, 0xb8);

    if(debug_info)
        printf("mb ");
    short int mb = i2c_read_int(file, 0xba);

    if(debug_info)
        printf("mc ");
    short int mc = i2c_read_int(file, 0xbc);

    if(debug_info)
        printf("md ");
    short int md = i2c_read_int(file, 0xbe);

    char buf1[2] = { 0xF4, 0x2E };
    i2c_write_bytes(file, buf1, 2);

    usleep(4500);               // 4.5 msec
    if(debug_info) {
        printf("write 0xF4, 0x2E, and wait 4.5msec\nut ");
    }

    unsigned int ut = i2c_read_int(file, 0xf6);

    char buf2[2] = { 0xF4, 0x34 + (BMP085_OVERSAMPLING_SETTING << 6) };
    i2c_write_bytes(file, buf2, 2);

    // wait 7.5ms (if oss=1), 13.5ms (oss=2), 25.5ms (oss=3)
    usleep(25.5 * 1000);
    if(debug_info) {
        printf("write 0xF4, 0x%02X, and wait 25.5msec\nup ",
               0x34 + (BMP085_OVERSAMPLING_SETTING << 6));
    }
    char buf_up[3] = { };
    i2c_read_bytes(file, 0xf6, buf_up, 3);

    unsigned int up =
        (buf_up[0] << 16 | buf_up[1] << 8 | buf_up[2]) >> (8 - BMP085_OVERSAMPLING_SETTING);
    if(debug_info)
        printf("(long %d)\n", up);

    // i2cデバイスを閉じる
    close(file);
    // GPIO 4 をBMP085の電源として利用する設定
#ifdef WIRING_PI
    digitalWrite(GPIO_WRITE_PIN, LOW);
#else
    system("gpio -g write 4 0");
#endif

    int b5 = 0;

    *t = (float) bmp085_calc_temperature(ut, ac5, ac6, mc, md, &b5) / 10.0;

    if(debug_info)
        printf("t = %f (deg-C)\n", *t);

    *p = (float) bmp085_calc_pressure(ac1, ac2, ac3, ac4, up, b1, b2, b5) / 100.0;

    if(debug_info)
        printf("p = %f (hPa)\n", *p);

    return;
}

int main(int argc, char **argv)
{
    float t, p;

    bmp085_getvalue(&t, &p);
    printf("BMP085\ntemperature = %.1f deg-C, pressure = %.2f hPa\n", t, p);

    return 0;
}
