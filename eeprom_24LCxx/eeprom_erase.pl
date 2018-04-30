#!/usr/bin/perl

# Microchip I2C EEPROM 24LC32/64/128/256/512 一部消去プログラム
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
my $erase_bytes = 1;        # 上書きバイト数
my $padding = 0;            # 上書きする文字

print("Microchip I2C EEPROM 24LC32/64/../512 erase program\n usage : $0 start_addr bytes padding_num\n");

if(@ARGV == 3){
    $start_addr = $ARGV[0] + 0;
    $erase_bytes = $ARGV[1] + 0;
    $padding = $ARGV[2] + 0;
}
else{
    print("error:parameter is few or more\n");
    exit;
}

if($start_addr < 0 || 8192 <= $start_addr){ $start_addr = 0; }
if($start_addr + $erase_bytes < 0 || 8192 <= $start_addr + $erase_bytes){
    $erase_bytes = 1;
}
$padding &= 0xff;

eval {
    my $fh = IO::File->new("/dev/i2c-1", O_RDWR);
    $fh->ioctl(I2C_SLAVE_FORCE, $i2c_addr);
    $fh->binmode();
    printf("open success:i2c device /dev/i2c-1, address %02X\n\n", $i2c_addr);

    # ダンプ先頭行 カラム番号表示
    print("addr | data\n-----------\n");
    
    # EEPROM書き込み
    for(my $i=$start_addr; $i<$start_addr + $erase_bytes; $i++){
        # 1Bytes書き込みは最悪条件で5.3ミリ秒掛かるため, 10ミリ秒待つ
        usleep(10*1000);
        my $buffer = pack("C*", $i>>8, $i&0xff, $padding);
        # アドレス 2Bytes + データ 1Byte 送信
        $fh->syswrite($buffer);
        printf("%04X | %02X (%02X %02X)\n", $i, $padding, $i>>8, $i&0xff);
    }
    print("\n");
    $fh->close();
};
if($@){
    die "\n".$@;
}
