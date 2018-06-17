#!/usr/bin/perl

# INA219 電流・電圧センサー Library
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

use constant INA219_I2C_ADDRESS => 0x40;

use constant INA219_REG_CONFIG        => 0x00;
use constant INA219_REG_SHUNT_VOLTAGE => 0x01;
use constant INA219_REG_BUS_VOLTAGE   => 0x02;
use constant INA219_REG_CURRENT       => 0x04;
use constant INA219_REG_CALIBRATION   => 0x05;

# デバッグ時に1とすることで、計算途中の変数を端末に表示する
my $__debug = 0;

############
# 実測と理論値を比較

# 回路 Shunt 0.1 ohm + R 22 ohm + VR 300 ohm

# (1) VR=0 ohmの場合 sigma_R=22.2 ohm, i=0.195 A, v=4.33V

#pi@raspberrypi:~/workspace/subfact_pi_ina219 $ perl ../ina219_debug.pl
#INA219 32V 2A
# Bus 0.656 V
# Shunt -18.41 mV
# i -184.4 mA
#INA219 16V 0.5A
# Bus 0.88 V
# Shunt -18.43 mV
# i -184.4 mA
#pi@raspberrypi:~/workspace/subfact_pi_ina219 $ python ./ina219_example.py
#Shunt   : -18.470 mV
#Bus     : 0.896 V
#Current : -185.000 mA

# (2) VR=300 ohmの場合 sigma_R=322 ohm, i=0.0150 A, v=4.84V

#pi@raspberrypi:~/workspace/subfact_pi_ina219 $ perl ../ina219_debug.pl
#INA219 32V 2A
# Bus 0.884 V
# Shunt -1.54 mV
# i -15.5 mA
#INA219 16V 0.5A
# Bus 0.848 V
# Shunt -1.54 mV
# i -15.3 mA
#pi@raspberrypi:~/workspace/subfact_pi_ina219 $ python ./ina219_example.py
#Shunt   : -1.530 mV
#Bus     : 0.768 V
#Current : -16.000 mA

############

{
    my ( $bus_v, $shunt_v, $i ) = ( 0.0, 0.0, 0.0 );

    ina219_init_32v01ma();
    usleep( 100 * 1000 );
    ( $bus_v, $shunt_v, $i ) = ina219_getvalue( 0.1, 8 );

    print "INA219 32V LSB=0.1mA\n Bus $bus_v V\n Shunt $shunt_v mV\n i $i mA\n";

    usleep( 500 * 1000 );
    ina219_init_16v005ma();
    usleep( 100 * 1000 );
    ( $bus_v, $shunt_v, $i ) = ina219_getvalue( 0.05, 4 );

    print "INA219 16V LSB=0.05A\n Bus $bus_v V\n Shunt $shunt_v mV\n i $i mA\n";

}

# VBUS=32V, VSHUNT=320mV, 電流LSB=0.1mAで初期設定
sub ina219_init_32v01ma {

    eval {
        my $fh = IO::File->new( "/dev/i2c-1", O_RDWR );
        $fh->ioctl( I2C_SLAVE_FORCE, INA219_I2C_ADDRESS );
        $fh->binmode();

        # CALIBRATION, LSB 計算
        # 参考資料：https://github.com/adafruit/Adafruit_INA219/blob/master/Adafruit_INA219.cpp
        # 計算条件 VBUS=32V, VSHUNT=0.32V(320mV), R_SHUNT=0.1ohm
        # 最大電流 I = VSHUNT/RSHUNT = 3.2A → 2.0A
        # LSB = I/2^15 = 0.000061 A → 0.0001 A (0.1mA)
        # CALIBRATION = 0.04096 / (LSB*RSHUNT) = 4096 = 0x1000
        my @array_bytes = ( INA219_REG_CALIBRATION, 0x10, 0x00 );
        i2c_write_bytes( $fh, \@array_bytes );

        # CONFIG
        # 32V FSR (BRNG = 1), 320mV Gain /8 (PG=0b11),
        # 12bit Bus Voltage (BADC=0b1000), 12bit Shunt Voltage (SADC=0b0011), continuous (MODE=0b111)
        @array_bytes = ( INA219_REG_CONFIG, 0x3C, 0x1F );
        i2c_write_bytes( $fh, \@array_bytes );

        close($fh);

    };
    if ($@) {
        if ( $__debug == 1 ) { print "error : $@"; }
        return ( 0, 0 );
    }

}

# VBUS=16V, VSHUNT=160mV, 電流LSB=0.05mAで初期設定
sub ina219_init_16v005ma {

    eval {
        my $fh = IO::File->new( "/dev/i2c-1", O_RDWR );
        $fh->ioctl( I2C_SLAVE_FORCE, INA219_I2C_ADDRESS );
        $fh->binmode();

       # CALIBRATION, LSB 計算
       # 参考資料：https://github.com/adafruit/Adafruit_INA219/blob/master/Adafruit_INA219.cpp
       # 計算条件 VBUS=16V, VSHUNT=0.16V(160mV), R_SHUNT=0.1ohm
       # 最大電流 I = VSHUNT/RSHUNT = 1.6A → 1.0A
       # LSB = I/2^15 = 0.00003 A → 0.00005 A (0.05mA)
       # CALIBRATION = 0.04096 / (LSB*RSHUNT) = 8192 = 0x2000
        my @array_bytes = ( INA219_REG_CALIBRATION, 0x20, 0x00 );
        i2c_write_bytes( $fh, \@array_bytes );

        # CONFIG
        # 16V FSR (BRNG = 0), 160mV Gain /4 (PG=0b10),
        # 12bit Bus Voltage (BADC=0b1000), 12bit Shunt Voltage (SADC=0b0011), continuous (MODE=0b111)
        @array_bytes = ( INA219_REG_CONFIG, 0x14, 0x1F );
        i2c_write_bytes( $fh, \@array_bytes );

        close($fh);

    };
    if ($@) {
        if ( $__debug == 1 ) { print "error : $@"; }
        return ( 0, 0 );
    }

}

sub ina219_getvalue {
    my ( $i_lsb, $gain ) = @_;
    my ( $bus_v, $shunt_v, $i ) = ( 0.0, 0.0, 0.0 );

    eval {
        my $fh = IO::File->new( "/dev/i2c-1", O_RDWR );
        $fh->ioctl( I2C_SLAVE_FORCE, INA219_I2C_ADDRESS );
        $fh->binmode();

        if ( $gain == 8 ) {
            # Shunt電圧のLSBは0.01mV(10uV)固定, gain=8のとき15bitなので±0〜327mV
            my $voltage = i2c_read_int( $fh, INA219_REG_SHUNT_VOLTAGE );
            if ( $__debug == 1 ) {
                printf( "shunt voltage = %.2f mV (0x%04X) -- read_int\n",
                        $voltage * 0.01, $voltage );
            }
            $shunt_v = $voltage * 0.01;
        } elsif ( $gain == 4 ) {
            # Shunt電圧のLSBは0.01mV(10uV)固定, gain=8のとき14bitなので±0〜163mV
            my $voltage =
              i2c_read_unsigned_int( $fh, INA219_REG_SHUNT_VOLTAGE );
            if ( ( $voltage & 0x8000 ) != 0 ) {
                $voltage = $voltage & 0x3fff;
                $voltage = ( ( $voltage ^ 0x3fff ) + 1 ) * (-1.0);
            }
            if ( $__debug == 1 ) {
                printf( "shunt voltage = %.2f mV (0x%04X) -- read_int\n",
                        $voltage * 0.01, $voltage );
            }
            $shunt_v = $voltage * 0.01;
        }

        # Bus電圧のLSBは0.004V(4mV)固定, 13bit幅なので0〜32V
        my $voltage = i2c_read_unsigned_int( $fh, INA219_REG_BUS_VOLTAGE );
        if ( $__debug == 1 ) {
            printf( "bus voltage, Vbus = %.2f V (0x%04X, raw 0x%04X)\n",
                    ( $voltage >> 3 ) * 0.004,
                    ( $voltage >> 3 ), $voltage );
        }
        $bus_v = ( $voltage >> 3 ) * 0.004;

        # Shunt電流のLSB=可変mA(CALIBRATIONの結果で可変)
        my $current = i2c_read_int( $fh, INA219_REG_CURRENT );
        if ( $__debug == 1 ) {
            printf( "current = %.2f mA (0x%04X)\n",
                    $current * $i_lsb, $current );
        }
        $i = $current * $i_lsb;

        close($fh);

    };
    if ($@) {
        if ( $__debug == 1 ) { print "error : $@"; }
        return ( $bus_v, $shunt_v, $i );
    }
    return ( $bus_v, $shunt_v, $i );

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
        $val = unpack( "n", $buffer ); # ビッグエンディアンのshort unsigned intとして解釈
    }

    if ( $__debug == 1 ) {
        printf "(0x%02X) = 0x%02X, 0x%02X (uint %u)\n", $i2c_reg,
          unpack( "C", substr( $buffer, 0, 1 ) ),
          unpack( "C", substr( $buffer, 1, 1 ) ), $val;
    }

    return $val;
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
    } else {
        my $val0 = unpack( "n", $buffer ); # ビッグエンディアンのshort unsigned intとして解釈
        $val = unpack( "s", pack( "S", $val0 ) ); # unsigned から signed に変換
    }

    if ( $__debug == 1 ) {
        printf "(0x%02X) = 0x%02X, 0x%02X (int %d)\n", $i2c_reg,
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

