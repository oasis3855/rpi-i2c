#!/usr/bin/perl

use strict;
use warnings;
use RPi::I2C;
use IO::File;
use Fcntl;


# https://mirrors.edge.kernel.org/pub/linux/kernel/people/marcelo/linux-2.4/include/linux/i2c.h
use constant I2C_SMBUS_READ     => 1;
use constant I2C_SMBUS_WRITE    => 0;

use constant I2C_SLAVE          => 0x0703;
use constant I2C_SLAVE_FORCE    => 0x0706;
use constant I2C_RDWR           => 0x0707;



my $i2c_addr = 0x51;

my $start_addr = 0x127;      # 書き込み開始アドレス
my $process_bytes = 1;      # 書き込みByte数
my $padding = 0xb0;         # 書き込む文字

print "Microchip I2C EEPROM test\n";

print "\nselect method\n  1 : RPi::I2C\n  2 : FILE write\n  3 : FILE read\n==>";
my $user_input = <STDIN>;
chomp($user_input);
$user_input = $user_input + 0;
if($user_input < 1 || 3 < $user_input){
    print "error: selected $user_input is out of range\n";
    exit;
}


if($user_input == 1){
    print "use RPi::I2C...\n";
    my $i2c = RPi::I2C->new($i2c_addr, "/dev/i2c-1");
    my @bytes = ($start_addr & 0xff, $padding);
    $i2c->write_block(\@bytes);
    print "done.\n";
}
elsif($user_input == 2){
    print "use IO::FILE...\n";
    eval {
        my $fh = IO::File->new("/dev/i2c-1", O_RDWR);
        $fh->ioctl(I2C_SLAVE_FORCE, $i2c_addr);
        $fh->binmode();
        # アドレス 2Bytes + データ 1Byte をバイナリ形式の変数に格納
        my $buffer = pack("C*", $start_addr >> 8, $start_addr & 0xff, $padding);
        # アドレス 2Bytes + データ 1Byte 送信
        #（bufferdのprintではなく、unbufferdのsyswrite利用）
        $fh->syswrite($buffer);
        $fh->close();
    };
    if($@){
        die $@;
    }
    print "done.\n";
}
elsif($user_input == 3){
    print "use IO::FILE read...\n";
    eval {
        my $fh = IO::File->new("/dev/i2c-1", O_RDWR);
        $fh->ioctl(I2C_SLAVE_FORCE, $i2c_addr);
        $fh->binmode();
        # アドレス 2Bytes をバイナリ形式の変数に格納
        my $buffer = pack("C*", $start_addr >> 8, $start_addr & 0xff);
        # アドレス 2Bytes 送信
        #（bufferdのprintではなく、unbufferdのsyswrite利用）
        $fh->syswrite($buffer);
        # データ 1Byte 受信
        #（bufferdのreadではなく、unbufferdのsysread利用）
        $fh->sysread($buffer, $process_bytes);
        $fh->close();
        
        printf "%X\n", unpack("C", substr($buffer,0,1));
    };
    if($@){
        die $@;
    }
    print "done.\n";
}

exit;

