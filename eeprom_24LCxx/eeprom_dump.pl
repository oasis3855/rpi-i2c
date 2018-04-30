#!/usr/bin/perl

# Microchip I2C EEPROM 24LC32/64/128/256/512 ダンプ出力プログラム
# for Raspberry Pi

use strict;
use warnings;
use IO::File;
use Fcntl;
use Time::HiRes 'usleep';

# https://mirrors.edge.kernel.org/pub/linux/kernel/people/marcelo/linux-2.4/include/linux/i2c.h
use constant I2C_SLAVE          => 0x0703;
use constant I2C_SLAVE_FORCE    => 0x0706;
use constant I2C_RDWR           => 0x0707;

my $i2c_addr = 0x51;

my $start_addr = 0;         # 開始行（16Bytes毎の行数）
my $disp_lines = 5;         # 表示行数（16Bytesで1行）

print("Microchip I2C EEPROM 24LC32/64/../512 dump program\n usage : $0 [start_addr lines]\n");

if(@ARGV == 2){
    $start_addr = $ARGV[0] + 0;
    $disp_lines = $ARGV[1] + 0;
}

if($start_addr < 0 || 512 < $start_addr){ $start_addr = 0; }
if($start_addr + $disp_lines < 0 || 512 < $start_addr + $disp_lines){
    $disp_lines = 0;
}

eval {
    my $fh = IO::File->new("/dev/i2c-1", O_RDWR);
    $fh->ioctl(I2C_SLAVE_FORCE, $i2c_addr);
    $fh->binmode();
    printf("open success:i2c device /dev/i2c-1, address %02X\n\n", $i2c_addr);

    # ダンプ先頭行 カラム番号表示
    print("        ");
    for(my $j=0; $j<0x10; $j++){ printf("%02X ", $j); }
    print("\n        ");
    for(my $j=0; $j<0x10; $j++){ print("---"); }
    print("\n");
    
    # EEPROM内容をダンプ出力する
    for(my $i=$start_addr; $i<$start_addr + $disp_lines; $i++){
        printf("%04X  | ", $i*16);
        for(my $j=0; $j<0x10; $j++){
            # 1Bytes書き込みは最悪条件で5.3ミリ秒掛かるため, 10ミリ秒待つ
            usleep(10*1000);
            # 読み出しアドレス（32kbit〜512kbitは2Bytesアドレス
            my $buffer = pack("C*", ($i*0x10+$j)>>8, ($i*0x10+$j)&0xff);
            # アドレス 2Bytes 送信
            $fh->syswrite($buffer);
            # アドレス送信後、1Bytes読みだす
            $fh->sysread($buffer, 1);
            # 受信データ 1Byteを表示する
            printf "%02X ", unpack("C", substr($buffer,0,1));
        }
        print("\n");
    }
    print("\n");
    $fh->close();
};
if($@){
    die "\n".$@;
}
