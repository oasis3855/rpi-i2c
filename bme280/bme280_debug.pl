#!/usr/bin/perl

# BOSCH BME280 - Digital pressure sensor Library
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

use constant BMP280_I2C_ADDRESS => 0x76;

use constant BMP280_TEMP_OSS     => 0x01;  # osrs_t = 0b001  -> oversampling x 1
use constant BMP280_PRES_OSS     => 0x01;  # osrs_p = 0b001  -> oversampling x 1
use constant BME280_HUM_OSS      => 0x01;  # osrs_h = 0b001  -> oversampling x 1
use constant BMP280_POWER_NORMAL => 0x03;  # power on (normalmode)
use constant BMP280_POWER_SLEEP  => 0x00;  # sleep
use constant BMP280_TIME_STANDBY => 0x05;  # standby 1000 msec
use constant BMP280_FILTER_OFF   => 0x00;  # filter off
use constant BMP280_SPI_OFF      => 0x00;  # SPI interface OFF

# デバッグ時に1とすることで、計算途中の変数を端末に表示する
my $__debug = 1;

{
    my ( $t, $p, $h ) = bmp280_getvalue();
    printf( "BME280\ntemperature = %.2f deg-C, pressure = %.2f hPa, humid = %.2f\n", $t, $p, $h );
    exit;
}

# 温度・気圧を配列で返すsub
sub bmp280_getvalue {
    my ( $t, $p, $h ) = ( 0, 0, 0 );

    eval {
        my $fh = IO::File->new( "/dev/i2c-1", O_RDWR );
        $fh->ioctl( I2C_SLAVE_FORCE, BMP280_I2C_ADDRESS );
        $fh->binmode();

        #
        # read ID
        #
        if ( $__debug == 1 ) {
            my $id = i2c_read_unsigned_int( $fh, 0xd0 );
            printf "id = 0x%04X (BMP280=56,57,58, BME280=60)\n", $id & 0x00ff;
        }
        #
        # read Trimming parameter
        #
        if ( $__debug == 1 ) { print "dig_t1 "; }
        my $dig_t1 = i2c_read_unsigned_int( $fh, 0x88 );
        if ( $__debug == 1 ) { print "dig_t2 "; }
        my $dig_t2 = i2c_read_int( $fh, 0x8a );
        if ( $__debug == 1 ) { print "dig_t3 "; }
        my $dig_t3 = i2c_read_int( $fh, 0x8c );
        if ( $__debug == 1 ) { print "dig_p1 "; }
        my $dig_p1 = i2c_read_unsigned_int( $fh, 0x8e );
        if ( $__debug == 1 ) { print "dig_p2 "; }
        my $dig_p2 = i2c_read_int( $fh, 0x90 );
        if ( $__debug == 1 ) { print "dig_p3 "; }
        my $dig_p3 = i2c_read_int( $fh, 0x92 );
        if ( $__debug == 1 ) { print "dig_p4 "; }
        my $dig_p4 = i2c_read_int( $fh, 0x94 );
        if ( $__debug == 1 ) { print "dig_p5 "; }
        my $dig_p5 = i2c_read_int( $fh, 0x96 );
        if ( $__debug == 1 ) { print "dig_p6 "; }
        my $dig_p6 = i2c_read_int( $fh, 0x98 );
        if ( $__debug == 1 ) { print "dig_p7 "; }
        my $dig_p7 = i2c_read_int( $fh, 0x9a );
        if ( $__debug == 1 ) { print "dig_p8 "; }
        my $dig_p8 = i2c_read_int( $fh, 0x9c );
        if ( $__debug == 1 ) { print "dig_p9 "; }
        my $dig_p9 = i2c_read_int( $fh, 0x9e );
        my $dig_h1 = i2c_read_unsigned_int( $fh, 0xa0 ) >> 8;   # 上位8ビット アドレス 0xa1 のみ
        if ( $__debug == 1 ) { print "dig_h1 = $dig_h1\n"; }
        if ( $__debug == 1 ) { print "dig_h2 "; }
        my $dig_h2 = i2c_read_int( $fh, 0xe1 );
        my $dig_h3 = i2c_read_unsigned_int( $fh, 0xe3 ) & 0xff;
        if ( $__debug == 1 ) { print "dig_h3 = $dig_h3\n"; }
        my $dig_h4 = ((i2c_read_unsigned_int( $fh, 0xe4 ) & 0xff) << 4) |
             (i2c_read_unsigned_int( $fh, 0xe5 ) & 0x0f);
        if(( $dig_h4 & 0x0800 ) != 0 ) {
            $dig_h4 = $dig_h4 & 0x07ff;
            $dig_h4 = ( ( $dig_h4 ^ 0x07ff ) + 1 ) * (-1.0);
        }
        if ( $__debug == 1 ) { print "dig_h4 = $dig_h4\n"; }
        my $dig_h5 = ((i2c_read_unsigned_int( $fh, 0xe6 ) & 0xff) << 4) |
             ((i2c_read_unsigned_int( $fh, 0xe5 ) & 0xf0) >> 4);
        if(( $dig_h5 & 0x0800 ) != 0 ) {
            $dig_h5 = $dig_h5 & 0x07ff;
            $dig_h5 = ( ( $dig_h5 ^ 0x07ff ) + 1 ) * (-1.0);
        }
        if ( $__debug == 1 ) { print "dig_h5 = $dig_h5\n"; }
        my $dig_h6 = i2c_read_unsigned_int( $fh, 0xe7 ) & 0xff;
        if(( $dig_h6 & 0x0080 ) != 0 ) {
            $dig_h6 = $dig_h6 & 0x007f;
            $dig_h6 = ( ( $dig_h6 ^ 0x007f ) + 1 ) * (-1.0);
        }
        if ( $__debug == 1 ) { print "dig_h6 = $dig_h6\n"; }

        #
        # Write 0xF2 "ctrl_hum" register sets
        # Controls oversampling of temperature and pressure data
        #
        my @array_bytes = ( 0xF2, BME280_HUM_OSS );
        i2c_write_bytes( $fh, \@array_bytes );
        if ( $__debug == 1 ) {
            printf "write 0xF2, 0x%02X (ctrl_hum)\n", $array_bytes[1];
        }

        #
        # Write 0xF4 "ctrl_meas" register sets
        # Controls oversampling of temperature and pressure data
        #
        @array_bytes = (
               0xF4,
               BMP280_TEMP_OSS << 5 | BMP280_PRES_OSS << 3 | BMP280_POWER_NORMAL
        );
        i2c_write_bytes( $fh, \@array_bytes );
        if ( $__debug == 1 ) {
            printf "write 0xF4, 0x%02X (ctrl_meas)\n", $array_bytes[1];
        }

        #
        # Write 0xF5 "config" register sets
        # Set stand by time = 1000ms (t_sb=0b101)
        #
        @array_bytes = (
               0xF5,
               BMP280_TIME_STANDBY << 5 | BMP280_FILTER_OFF << 1 | BMP280_SPI_OFF );
        i2c_write_bytes( $fh, \@array_bytes );
        if ( $__debug == 1 ) {
            printf "write 0xF4, 0x%02X (config)\n", $array_bytes[1];
        }
        usleep( 1000 * 1000 );

        #
        # Read raw temperature, pressure and humidity measurement output
        #
        my $data_bytes = i2c_read_bytes( $fh, 0xf7, 8 );
        if ( length($data_bytes) != 8 ) {
            close($fh);
            return ( 0, 0, 0 );
        }

        my $adc_p =
          unpack( "C", substr( $data_bytes, 0, 1 ) ) << 12 |
          unpack( "C", substr( $data_bytes, 1, 1 ) ) << 4 |
          unpack( "C", substr( $data_bytes, 2, 1 ) ) >> 4;
        if ( $__debug == 1 ) {
            printf "adc_p = %ld (0x%06X)\n", $adc_p, $adc_p;
        }
        my $adc_t =
          unpack( "C", substr( $data_bytes, 3, 1 ) ) << 12 |
          unpack( "C", substr( $data_bytes, 4, 1 ) ) << 4 |
          unpack( "C", substr( $data_bytes, 5, 1 ) ) >> 4;
        if ( $__debug == 1 ) {
            printf "adc_p = %ld (0x%06X)\n", $adc_t, $adc_t;
        }
        my $adc_h =
          unpack( "C", substr( $data_bytes, 6, 1 ) ) << 8 |
          unpack( "C", substr( $data_bytes, 7, 1 ) );
        if ( $__debug == 1 ) {
            printf "adc_h = %ld (0x%06X)\n", $adc_h, $adc_h;
        }

        #
        # Calc temperature
        #
        my $var1 = ( $adc_t / 16384.0 - $dig_t1 / 1024.0 ) * $dig_t2;
        my $var2 =
          ( ( $adc_t / 131072.0 - $dig_t1 / 8192.0 ) *
            ( $adc_t / 131072.0 - $dig_t1 / 8192.0 ) ) *
          $dig_t3;
        my $t_fine = $var1 + $var2;
        $t = ( $var1 + $var2 ) / 5120.0;
        #
        # Calc pressure
        #
        $var1 = ( $t_fine / 2.0 ) - 64000.0;
        $var2 = $var1 * $var1 * $dig_p6 / 32768.0;
        $var2 = $var2 + $var1 * $dig_p5 * 2.0;
        $var2 = ( $var2 / 4.0 ) + ( $dig_p4 * 65536.0 );
        $var1 =
          ( $dig_p3 * $var1 * $var1 / 524288.0 + $dig_p2 * $var1 ) / 524288.0;
        $var1 = ( 1.0 + $var1 / 32768.0 ) * $dig_p1;
        $p    = 1048576.0 - $adc_p;
        $p    = ( $p - ( $var2 / 4096.0 ) ) * 6250.0 / $var1;
        $var1 = $dig_p9 * $p * $p / 2147483648.0;
        $var2 = $p * $dig_p8 / 32768.0;
        $p    = ( $p + ( $var1 + $var2 + $dig_p7 ) / 16.0 ) / 100;
        #
        # Calc humidity
        #
        my $var_h = $t_fine - 76800.0;
        $var_h = ( $adc_h - ( $dig_h4 * 64.0 + $dig_h5 / 16384.0 * $var_h ) ) * 
            ( $dig_h2 / 65536.0 * ( 1.0 + $dig_h6 / 67108864.0 * $var_h *
            ( 1.0 + $dig_h3 / 67108864.0 * $var_h ) ) );
        $var_h = $var_h * ( 1.0 - $dig_h1 * $var_h / 524288.0 );
        if ( $__debug == 1 ) { print "raw var_h = $var_h\n"; }
        if( $var_h > 100.0 ){ $var_h = 100.0; }
        elsif( $var_h < 0.0 ){ $var_h = 0.0; }
        $h = $var_h;

        #
        # Write 0xF4 "ctrl_meas" register sets
        # Controls oversampling of temperature and pressure data
        #
        @array_bytes = (
                0xF4,
                BMP280_TEMP_OSS << 5 | BMP280_PRES_OSS << 3 | BMP280_POWER_SLEEP
        );
        i2c_write_bytes( $fh, \@array_bytes );
        if ( $__debug == 1 ) {
            printf "write 0xF4, 0x%02X (Sleep)\n", $array_bytes[1];
        }

        close($fh);

    };
    if ($@) {
        if ( $__debug == 1 ) { print "error : $@"; }
        return ( 0, 0, 0 );
    }

    return ( $t, $p, $h );

}

sub i2c_read_int {
    my ( $i2c, $i2c_reg ) = @_;
    my $val = 0;

    # アドレス 2Bytes をバイナリ形式の変数に格納
    my $buffer = pack( "C*", $i2c_reg );

    # アドレス 2Bytes 送信
    #（bufferdのprintではなく、unbufferdのsyswrite利用）
    $i2c->syswrite($buffer);

    # データ 2Bytes 受信
    #（bufferdのreadではなく、unbufferdのsysread利用）
    my $read_bytes = $i2c->sysread( $buffer, 2 );
    if ( !defined($read_bytes) || $read_bytes != 2 ) {
        if ( $__debug == 1 ) {
            print "error : less than 2 bytes data read from I2C device\n";
        }
    }
    else{
        my $val0 = unpack( "v", $buffer ); # リトルエンディアンのshort unsigned intとして解釈
        $val = unpack( "s", pack( "S", $val0 ) ); # unsigned から signed に変換
    }

    if ( $__debug == 1 ) {
        printf "(0x%02X) = 0x%02X, 0x%02X (int %d)\n", $i2c_reg,
          unpack( "C", substr( $buffer, 0, 1 ) ),
          unpack( "C", substr( $buffer, 1, 1 ) ), $val;
    }

    return $val;
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
            print "error : less than 2 bytes data read from I2C device\n", ;
        }
    }
    else{
        $val = unpack( "v", $buffer ); # リトルエンディアンのshort unsigned intとして解釈
    }

    if ( $__debug == 1 ) {
        printf "(0x%02X) = 0x%02X, 0x%02X (uint %u)\n", $i2c_reg,
          unpack( "C", substr( $buffer, 0, 1 ) ),
          unpack( "C", substr( $buffer, 1, 1 ) ), $val;
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

