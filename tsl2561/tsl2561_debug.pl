#!/usr/bin/perl

# TSL2561 - light-to-digital converter Library
# for Raspberry Pi
use strict;
use warnings;
use IO::File;
use Fcntl;
use Time::HiRes 'usleep';

# https://mirrors.edge.kernel.org/pub/linux/kernel/people/marcelo/linux-2.4/include/linux/i2c.h
use constant I2C_SLAVE       => 0x0703;
use constant I2C_SLAVE_FORCE => 0x0706;
use constant I2C_RDWR        => 0x0707;

use constant TSL2561_I2C_ADDRESS => 0x39;

# Command Registerの上位4ビットでアクセス方法を指定する
use constant TSL2561_CMD_WORD => 0xa0;
use constant TSL2561_CMD      => 0x80;

# Command Registerの下位4ビットでRegister Addressを指定する
use constant TSL2561_REG_CONTROL => 0x00;
use constant TSL2561_REG_TIMING  => 0x01;
use constant TSL2561_REG_ID      => 0x0a;
use constant TSL2561_REG_DATA0   => 0x0c;
use constant TSL2561_REG_DATA1   => 0x0e;

use constant TSL2561_PWR_ON  => 0x03;
use constant TSL2561_PWR_OFF => 0x00;

use constant TSL2561_LOW_GAIN => 0;    # gain = x1
use constant TSL2561_HIGH_GAIN => 0x10; # gain = x16, 暗所で測定値が小さい場合
use constant TSL2561_INTTIME_402 => 0x02;

# デバッグ時に1とすることで、計算途中の変数を端末に表示する
my $__debug = 1;

{
    system "gpio -g mode 4 down";
    system "gpio -g mode 4 out";
    system "gpio -g write 4 1";
    my ( $ch0_lux, $ch1_lux ) = tsl2561_getvalue(TSL2561_LOW_GAIN);
    my ( $part_no, $rev_no )  = tsl2561_getver();
    my $lux = tsl2561_calc_lux( $ch0_lux, $ch1_lux, $part_no );
    printf( "TSL2561 (part=%d, rev=%d)\nch0 raw = %d, ch1 raw = %d, Lux = %d\n",
            , $part_no, $rev_no, $ch0_lux, $ch1_lux, $lux );
    system "gpio -g write 4 0";
    exit;

}

# TSL2561より照度の生データ（可視光＋赤外、赤外）の読み出し
sub tsl2561_getvalue {
    my $gain = shift;
    my ( $ch0_lux, $ch1_lux ) = ( 0, 0 );

    eval {
        my $fh = IO::File->new( "/dev/i2c-1", O_RDWR );
        $fh->ioctl( I2C_SLAVE_FORCE, TSL2561_I2C_ADDRESS );
        $fh->binmode();

        # Control Register (0h) : 電源ON
        my @array_bytes = ( TSL2561_CMD | TSL2561_REG_CONTROL, TSL2561_PWR_ON );
        i2c_write_bytes( $fh, \@array_bytes );

        # Timing Register (1h) : 増幅（gain）とチャージ時間の設定
        @array_bytes =
          ( TSL2561_CMD | TSL2561_REG_TIMING, $gain | TSL2561_INTTIME_402 );
        i2c_write_bytes( $fh, \@array_bytes );

        # TSL2561_INTTIME_402 の場合は 402ms 以上待つ
        usleep( 1000 * 1000 );

        $ch0_lux =
          i2c_read_unsigned_int( $fh, TSL2561_CMD | TSL2561_REG_DATA0 );
        $ch1_lux =
          i2c_read_unsigned_int( $fh, TSL2561_CMD | TSL2561_REG_DATA1 );
        if ( $gain == TSL2561_LOW_GAIN ) {
            $ch0_lux *= 16;
            $ch1_lux *= 16;
        }
        if ( $__debug == 1 ) {
            printf( "CH0 = 0x%04X (%d)  (ir and visible sensor)\n",
                    $ch0_lux, $ch0_lux );
            printf( "CH1 = 0x%04X (%d)  (ir sensor)\n", $ch1_lux, $ch1_lux );
        }

        # Control Register (0h) : 電源OFF
        @array_bytes = ( TSL2561_CMD | TSL2561_REG_CONTROL, TSL2561_PWR_OFF );
        i2c_write_bytes( $fh, \@array_bytes );

        close($fh);

    };
    if ($@) {
        if ( $__debug == 1 ) { print "error : $@"; }
        return ( 0, 0 );
    }

    return ( $ch0_lux, $ch1_lux );
}

# ch0, ch1生データより、照度の計算
sub tsl2561_calc_lux {
    my ( $ch0, $ch1, $part_no ) = @_;
    my $lux = 0;

    if ( $ch0 == 0 ) {
        if ( $__debug == 1 ) { print "Warning : ch0 = 0 (divide by 0)\n"; }
        return $lux;
    }

    my $ch_ratio = ( $ch1 * 1.0 ) / $ch0;

    if ( $part_no == 4 || $part_no == 5 ) {

        # T/FN/CL パッケージの場合
        if ( $ch_ratio <= 0.50 ) {
            $lux = 0.0304 * $ch0 - 0.062 * $ch0 * ( $ch_ratio**1.4 );
        } elsif ( $ch_ratio <= 0.61 ) {
            $lux = 0.0224 * $ch0 - 0.031 * $ch1;
        } elsif ( $ch_ratio <= 0.80 ) {
            $lux = 0.0128 * $ch0 - 0.0153 * $ch1;
        } elsif ( $ch_ratio <= 1.30 ) {
            $lux = 0.00146 * $ch0 - 0.00112 * $ch1;
        } else {
            $lux = 0;
        }
        if ( $__debug == 1 ) { print "T/FN/CL package\n"; }
    } elsif ( $part_no == 0 || $part_no == 1 ) {

        # CS パッケージの場合
        if ( $ch_ratio <= 0.50 ) {
            $lux = 0.0315 * $ch0 - 0.0593 * $ch0 * ( $ch_ratio**1.4 );
        } elsif ( $ch_ratio <= 0.61 ) {
            $lux = 0.0229 * $ch0 - 0.0291 * $ch1;
        } elsif ( $ch_ratio <= 0.80 ) {
            $lux = 0.0157 * $ch0 - 0.0180 * $ch1;
        } elsif ( $ch_ratio <= 1.30 ) {
            $lux = 0.00338 * $ch0 - 0.00260 * $ch1;
        } else {
            $lux = 0;
        }
        if ( $__debug == 1 ) { print "CS package\n"; }
    } else {
        if ( $__debug == 1 ) { print "Error: unknown package\n"; }
    }

    if ( $__debug == 1 ) {
        printf( "ch1/ch0 = %.2f\n", $ch_ratio );
    }

    return $lux;
}

# ID Register (Ah) の読み出し
#
# 読みだしたPARTNOによるIC種類の判別
# PARTNO : 0b0000 = TSL2560CS, 0b0001 = TSL2561CS, 0b0100 = TSL2560T/FN/CL, 0b0101 = TSL2561T/FN/CL
sub tsl2561_getver {
    my ( $part_no, $rev_no ) = ( 0, 0 );

    eval {
        my $fh = IO::File->new( "/dev/i2c-1", O_RDWR );
        $fh->ioctl( I2C_SLAVE_FORCE, TSL2561_I2C_ADDRESS );
        $fh->binmode();

        # ID Register (Ah) の読み出し
        my $data_bytes = i2c_read_bytes( $fh, TSL2561_CMD | TSL2561_REG_ID, 1 );
        if ( length($data_bytes) == 1 ) {
            my $id_reg = unpack( "C", substr( $data_bytes, 0, 1 ) );
            $part_no = ( $id_reg & 0xf0 ) >> 4;
            $rev_no  = $id_reg & 0x0f;
        } else {
            if ( $__debug == 1 ) {
                print "Error : ID Register (Ah) read\n";
            }
        }
    };
    if ($@) {
        if ( $__debug == 1 ) { print "error : $@"; }
        return ( 0, 0 );
    }

    return ( $part_no, $rev_no );
}

sub i2c_write_bytes {
    my ( $i2c, $ref_array, $count ) = @_;

    # アドレス 2Bytes をバイナリ形式の変数に格納
    my $buffer = pack( "C*", @{$ref_array} );

    # アドレス 2Bytes 送信
    $i2c->syswrite($buffer);

    return;
}

sub i2c_read_unsigned_int {
    my ( $i2c, $i2c_reg ) = @_;
    my $val = 0;

    # アドレス 2Bytes をバイナリ形式の変数に格納
    my $buffer = pack( "C*", $i2c_reg );

    # アドレス 2Bytes 送信
    $i2c->syswrite($buffer);

    # データ 2Bytes 受信
    my $read_bytes = $i2c->sysread( $buffer, 2 );
    if ( !defined($read_bytes) || $read_bytes != 2 ) {
        if ( $__debug == 1 ) {
            print "error : less than 2 bytes data read from I2C device\n",;
        }
    } else {
        $val = unpack( "v", $buffer ); # リトルエンディアンのshort unsigned intとして解釈
    }

    if ( $__debug == 1 ) {
        printf "(0x%02X) = 0x%02X, 0x%02X (uint %u)\n", $i2c_reg,
          unpack( "C", substr( $buffer, 0, 1 ) ),
          unpack( "C", substr( $buffer, 1, 1 ) ), $val;
    }

    return $val;
}

sub i2c_read_bytes {
    my ( $i2c, $i2c_reg, $count ) = @_;

    # アドレス 2Bytes をバイナリ形式の変数に格納
    my $buffer = pack( "C*", $i2c_reg );

    # アドレス 2Bytes 送信
    $i2c->syswrite($buffer);

    # データ $count Byte 受信
    my $read_bytes = $i2c->sysread( $buffer, $count );
    if ( !defined($read_bytes) || $read_bytes != $count ) {
        $buffer = "";
        if ( $__debug == 1 ) {
            print "error : less than $count bytes data read from I2C device\n";
        }
    }
    if ( $__debug == 1 ) {
        printf( "(0x%02X) = ", $i2c_reg );
        for ( my $i = 0 ; $i < $count ; $i++ ) {
            printf( "0x%02X, ", unpack( "C", substr( $buffer, $i, 1 ) ) );
        }
        print "\n";
    }

    return $buffer;
}

