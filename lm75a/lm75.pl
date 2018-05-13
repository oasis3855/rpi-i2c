#!/usr/bin/perl

# NXP LM75A - Digital temperature sensor Library
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

use constant LM75_I2C_ADDRESS => 0x48;

{
    system "/usr/local/bin/gpio -g mode 4 out";
    system "/usr/local/bin/gpio -g write 4 1";
    my $t = lm75_getvalue();
    system "/usr/local/bin/gpio -g write 4 0";
    printf( "LM75\ntemperature = %.1f deg-C\n", $t );
    exit;
}

# 温度・気圧を配列で返すsub
sub lm75_getvalue {
    my $t = 0;

    eval {
        my $fh = IO::File->new( "/dev/i2c-1", O_RDWR );
        $fh->ioctl( I2C_SLAVE_FORCE, LM75_I2C_ADDRESS );
        $fh->binmode();

        # 0.1秒待つ(電源投入後に回路が安定するまで、適当な時間だけ待つ)
        usleep( 100 * 1000 );

        # LM75から2バイトのデータを読み込む
        my $data_bytes = i2c_read_bytes( $fh, 0, 2 );

        if ( length($data_bytes) == 2 ) {

            # 温度のデコード
            # 温度は、$data_bytes[2]に整数部,$data_bytes[3]に少数第一位の数値が入っている
            $t =
              unpack( "C", substr( $data_bytes, 0, 1 ) ) << 3 |
              ( unpack( "C", substr( $data_bytes, 1, 1 ) ) & 0xf0 ) >> 13;

            # 負数の場合の処理
            if ( $t & 0x0400 ) {
                $t = ( ~$t & 0x03ff );    # 1の補数
                $t += 1;                  # 2の補数
                $t *= -1;
            }

            $t *= 0.125;
        }

        close($fh);

    };
    if ($@) {
        return $t;
    }

    return $t;
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
    }

    return $buffer;
}
