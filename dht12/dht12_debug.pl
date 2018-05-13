#!/usr/bin/perl

# AOSONG DHT12 - Digital temperature and humidity sensor Library
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

use constant DHT12_I2C_ADDRESS => 0x5c;

# デバッグ時に1とすることで、計算途中の変数を端末に表示する
my $__debug = 1;

{
    system "/usr/local/bin/gpio -g mode 4 out";
    system "/usr/local/bin/gpio -g write 4 1";
    my ( $t, $h ) = dht12_getvalue();
    system "/usr/local/bin/gpio -g write 4 0";
    printf( "DHT12\ntemperature = %.1f deg-C, humidity = %.1f %%\n", $t, $h );
    exit;
}

# 温度・気圧を配列で返すsub
sub dht12_getvalue {
    my ( $t, $h ) = ( 0, 0 );

    eval {
        my $fh = IO::File->new( "/dev/i2c-1", O_RDWR );
        $fh->ioctl( I2C_SLAVE_FORCE, DHT12_I2C_ADDRESS );
        $fh->binmode();

        # DHT12電源ON後、2秒待つ
        # After power up (start wait 2 Seconds to cross the unstable condition of the sensor)
        usleep( 2000 * 1000 );

        # DHT12から5バイトのデータを読み込む
        my $data_bytes = i2c_read_bytes( $fh, 0, 5 );

        if ( length($data_bytes) == 5 ) {

            # チェックサムの計算
            my $checksum =
              unpack( "C", substr( $data_bytes, 0, 1 ) ) +
              unpack( "C", substr( $data_bytes, 1, 1 ) ) +
              unpack( "C", substr( $data_bytes, 2, 1 ) ) +
              unpack( "C", substr( $data_bytes, 3, 1 ) );
            if ( $__debug == 1 ) {
                printf "checksum = 0x%02X (%s)\n", $checksum & 0xff,
                  ( $checksum & 0xff ) ==
                  unpack( "C", substr( $data_bytes, 4, 1 ) ) ? 'OK' : 'NG';
            }

            if ( ( $checksum & 0xff ) ==
                 unpack( "C", substr( $data_bytes, 4, 1 ) ) )
            {
                # 湿度・温度のデコード
                # 湿度は、$data_bytes[0]に整数部,$data_bytes[1]に少数第一位の数値が入っている
                $h =
                  unpack( "C", substr( $data_bytes, 0, 1 ) ) +
                  unpack( "C", substr( $data_bytes, 1, 1 ) ) * 0.1;

                # 温度は、$data_bytes[2]に整数部,$data_bytes[3]に少数第一位の数値が入っている
                $t =
                  unpack( "C", substr( $data_bytes, 2, 1 ) ) +
                  unpack( "C", substr( $data_bytes, 3, 1 ) ) * 0.1;
            }
        }

        close($fh);

    };
    if ($@) {
        if ( $__debug == 1 ) { print "error : $@"; }
        return ( $t, $h );
    }

    return ( $t, $h );
}

sub i2c_read_bytes {
    my ( $i2c, $i2c_reg, $count ) = @_;

    # アドレス 2Bytes をバイナリ形式の変数に格納
    my $buffer = pack( "C*", $i2c_reg );

    # アドレス 2Bytes 送信
    $i2c->syswrite($buffer);

    # データ $count Byte 受信
    my $read_bytes = $i2c->sysread( $buffer, $count );

    # データ受信不能または$count未満の場合、空の$bufferを返す
    if ( !defined($read_bytes) || $read_bytes != $count ) {
        $buffer = "";
        if ( $__debug == 1 ) {
            print "error : less than $count bytes data read from I2C device\n";
        }
    }

    if ( $__debug == 1 ) {
        printf( "(0x%02X) = ", $i2c_reg );
        for ( my $i = 0 ; $i < length($buffer) ; $i++ ) {
            printf( "0x%02X, ", unpack( "C", substr( $buffer, $i, 1 ) ) );
        }
        print "\n";
    }

    return $buffer;
}

