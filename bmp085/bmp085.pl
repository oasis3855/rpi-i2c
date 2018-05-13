#!/usr/bin/perl

# BOSCH BMP085 - Digital pressure sensor Library
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

use constant BMP085_I2C_ADDRESS => 0x77;

# OSS : standard = 1, high resolution = 2, ultra high resolution = 3
use constant BMP085_OVERSAMPLING_SETTING => 3;

{
    system "gpio -g mode 4 out";
    system "gpio -g write 4 1";
    my ( $t, $p ) = bmp085_getvalue();
    system "gpio -g write 4 0";
    printf( "BMP085\ntemperature = %.1f deg-C, pressure = %.2f hPa\n",
            $t / 10, $p / 100 );
    exit;
}

# 温度・気圧を配列で返すsub
sub bmp085_getvalue {
    my ( $t, $p ) = ( 0, 0 );

    eval {
        my $fh = IO::File->new( "/dev/i2c-1", O_RDWR );
        $fh->ioctl( I2C_SLAVE_FORCE, BMP085_I2C_ADDRESS );
        $fh->binmode();

        #
        # read calibration data
        #
        my $ac1 = i2c_read_int( $fh, 0xaa );
        my $ac2 = i2c_read_int( $fh, 0xac );
        my $ac3 = i2c_read_int( $fh, 0xae );
        my $ac4 = i2c_read_unsigned_int( $fh, 0xb0 );
        my $ac5 = i2c_read_unsigned_int( $fh, 0xb2 );
        my $ac6 = i2c_read_unsigned_int( $fh, 0xb4 );
        my $b1 = i2c_read_int( $fh, 0xb6 );
        my $b2 = i2c_read_int( $fh, 0xb8 );
        my $mb = i2c_read_int( $fh, 0xba );
        my $mc = i2c_read_int( $fh, 0xbc );
        my $md = i2c_read_int( $fh, 0xbe );

        #
        # read uncompensated temperature value
        #
        my @array_bytes = ( 0xF4, 0x2E );
        i2c_write_bytes( $fh, \@array_bytes );

        # wait 4.5 ms
        usleep(4500);
        my $ut = i2c_read_int( $fh, 0xf6 );

        #
        # read uncompensated pressure value
        #
        @array_bytes = ( 0xF4, 0x34 + ( BMP085_OVERSAMPLING_SETTING << 6 ) );
        i2c_write_bytes( $fh, \@array_bytes );

        # wait 7.5ms (if oss=1), 13.5ms (oss=2), 25.5ms (oss=3)
        usleep( 25.5 * 1000 );

        #
        # Read raw temperature and pressure measurement output
        #
        my $data_bytes = i2c_read_bytes( $fh, 0xf6, 3 );
        if ( length($data_bytes) != 3 ) {
            close($fh);
            return ( 0, 0 );
        }
        my @up_array = unpack( "C*", $data_bytes );
        my $up = ( $up_array[0] << 16 | $up_array[1] << 8 | $up_array[2] )
          >> ( 8 - BMP085_OVERSAMPLING_SETTING );

        $fh->close();

        my $b5;
        ( $t, $b5 ) = bmp085_calc_temperature( $ut, $ac5, $ac6, $mc, $md );

        $p = bmp085_calc_pressure( $ac1, $ac2, $ac3, $ac4, $up, $b1, $b2, $b5 );

    };
    if ($@) {
        die $@;
    }

    return ( $t, $p );

}

sub bmp085_calc_temperature {
    my ( $ut, $ac5, $ac6, $mc, $md ) = @_;
    my ( $t, $b5, $x1, $x2 );
    $x1 = int( ( ( $ut - $ac6 ) * $ac5 ) / ( 2**15 ) );
    $x2 = int( ( $mc * ( 2**11 ) ) / ( $x1 + $md ) );
    $b5 = $x1 + $x2;
    $t  = int( ( $b5 + 8 ) / ( 2**4 ) );

    return ( $t, $b5 );
}

sub bmp085_calc_pressure {
    my ( $ac1, $ac2, $ac3, $ac4, $up, $b1, $b2, $b5 ) = @_;
    my ( $x1, $x2, $x3, $b3, $b4, $b6, $b7, $p );

    $b6 = int( $b5 - 4000 );

    $x1 = int( ( $b2 * ( $b6 * $b6 / ( 2**12 ) ) ) / ( 2**11 ) );
    $x2 = int( ( $ac2 * $b6 ) /                      ( 2**11 ) );
    $x3 = $x1 + $x2;
    $b3 =
      int( ( ( int( ($ac1) * 4 + $x3 ) << BMP085_OVERSAMPLING_SETTING ) + 2 ) /
           4 );

    $x1 = int( ( $ac3 * $b6 ) / ( 2**13 ) );
    $x2 = int( ( $b1 * ( $b6 * $b6 / ( 2**12 ) ) ) / ( 2**16 ) );
    $x3 = int( ( ( $x1 + $x2 ) + 2 ) / ( 2**2 ) );
    $b4 = int( $ac4 * int( $x3 + 32768 ) / ( 2**15 ) );

    $b7 = int( ( int($up) - $b3 ) * ( 50000 >> BMP085_OVERSAMPLING_SETTING ) );
    if   ( $b7 < 0x80000000 ) { $p = int( $b7 * 2 / $b4 ); }
    else                      { $p = int( $b7 / $b4 * 2 ); }

    $x1 = int( $p / ( 2**8 ) * $p / ( 2**8 ) );
    $x1 = int( ( $x1 * 3038 ) / ( 2**16 ) );
    $x2 = int( ( -7357 * $p ) / ( 2**16 ) );
    $p += int( ( $x1 + $x2 + 3791 ) / ( 2**4 ) );


    return $p;

}

sub i2c_read_int {
    my ( $i2c, $bmp085_reg ) = @_;
    my $val = 0;

    # アドレス 2Bytes をバイナリ形式の変数に格納
    my $buffer = pack( "C*", $bmp085_reg );

    # アドレス 2Bytes 送信
    #（bufferdのprintではなく、unbufferdのsyswrite利用）
    $i2c->syswrite($buffer);

    # データ 2Bytes 受信
    #（bufferdのreadではなく、unbufferdのsysread利用）
    my $read_bytes = $i2c->sysread( $buffer, 2 );
    if ( defined($read_bytes) && $read_bytes == 2 ) {
        my $val0 = unpack( "n", $buffer ); # ビッグエンディアンのshort unsigned intとして解釈
        $val = unpack( "s", pack( "S", $val0 ) ); # unsigned から signed に変換
    }

    return $val;
}

sub i2c_read_unsigned_int {
    my ( $i2c, $bmp085_reg ) = @_;
    my $val = 0;

    # アドレス 2Bytes をバイナリ形式の変数に格納
    my $buffer = pack( "C*", $bmp085_reg );

    # アドレス 2Bytes 送信
    $i2c->syswrite($buffer);

    # データ 2Bytes 受信
    my $read_bytes = $i2c->sysread( $buffer, 2 );
    if ( defined($read_bytes) && $read_bytes == 2 ) {
        $val = unpack( "n", $buffer ); # ビッグエンディアンのshort unsigned intとして解釈
    }

    return $val;
}

sub i2c_write_bytes {
    my ( $i2c, $ref_array, $count ) = @_;

    # アドレス 2Bytes をバイナリ形式の変数に格納
    my $buffer = pack( "C*", @{$ref_array} );

    # アドレス 2Bytes 送信
    $i2c->syswrite($buffer);

    return;
}

sub i2c_read_bytes {
    my ( $i2c, $bmp085_reg, $count ) = @_;

    # アドレス 2Bytes をバイナリ形式の変数に格納
    my $buffer = pack( "C*", $bmp085_reg );

    # アドレス 2Bytes 送信
    $i2c->syswrite($buffer);

    # データ $count Byte 受信
    my $read_bytes = $i2c->sysread( $buffer, $count );
    if ( !defined($read_bytes) || $read_bytes != $count ) {
        $buffer = "";
    }

    return $buffer;
}
