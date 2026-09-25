package Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::EPL;
use warnings;
use strict;
use utf8;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(toEPL);

use Koha::Patrons;
use Koha::DateUtils qw( dt_from_string output_pref );
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;

use Data::Dumper;
use Text::Unaccent;

sub _epl_config {
    my (%param) = @_;
    return Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({
        interface => 'letters',
        branch    => $param{'branchconfig'},
    })->rootConfig->{'ipostepl'} || {};
}

sub hdiacritic {
    my $char;
    my $oldchar;
    my $string;

    foreach ( split( //, $_[0] ) ) {
        $char    = $_;
        $oldchar = $char;
        unless ( $char =~ /[A-Za-z0-9ÅåÄäÖöÉéÜüÁá]/ ) {
            $char = 'Z'  if $char eq 'Ʒ';
            $char = 'z'  if $char eq 'ʒ';
            $char = 'B'  if $char eq 'ß';
            $char = '\'' if $char eq 'ʻ';
            $char = 'e'  if $char eq '€';
            $char = unac_string( 'utf-8', $char ) if "$oldchar" eq "$char";
        }
        $string .= $char;
    }

    return $string;
}

sub letterBody {
    my %param = @_;

    my $epl = _epl_config( 'branchconfig' => $param{'branchconfig'} );
    my $contpagecode = $epl->{'layout'}->{'contpagecode'} || '';
    my $firstpage = $epl->{'layout'}->{'firstpage'};
    my $otherpages = $epl->{'layout'}->{'otherpages'};

    my $message;
    my $lines = 0;
    my $pages = 1;

    foreach my $line ( split /\r?\n/, hdiacritic ( $param{'content'} ) ) {
         if ( $lines == 0 ) {
             $line = '30'. $line . "\r\n";
             $lines++
         }
         elsif ( ($contpagecode ne '') && ( ( $pages == 1 && $lines == $firstpage ) or ( $lines == $otherpages ) ) ) {
             $line = ' 0' . $line . "\r\n" . '10' . "\r\n" . $contpagecode . "\r\n";
             $pages++;
             $lines = 1;
         }
         else {
             $line = ' 0' . $line . "\r\n";
         }

         $message .= $line;
         $lines++
    }

    return $message;
}

sub fixZip {
    my $zipcode =  shift;
       $zipcode =~ s/-//g;
       $zipcode =  'FI'. $zipcode if ( $zipcode =~ /^[0-9]/ );

    return $zipcode;
}

sub EPLHeader {
    my %param = @_;

    my $config = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({
        interface => 'letters',
        branch    => $param{'branchconfig'},
    });
    my $ipostcontact = $config->contact;
    my $eplheader = _epl_config( 'branchconfig' => $param{'branchconfig'} )->{'header'};

    return $eplheader . ' ' x 16 . $ipostcontact . "\r\n";
}

sub letterHeader {
    my %param = @_;

    my $somecode;
    my $templatecode;

    my $epl = _epl_config( 'branchconfig' => $param{'branchconfig'} );
    $somecode = $epl->{'code'};
    $templatecode = $epl->{'layout'}->{'templatecode'};

    my $letterheader = sprintf ( "%-14s", 'EPLK' . fixZip ( $param{'zipcode'} ) )
                     . sprintf ( "%-26s", '100' ) . $somecode . "\r\n"
                     . '10' . ' ' x 44 . $param{'subject'} . "\r\n"
                     . ' 0' . ' ' x 44 . $param{'date'} . "\r\n"
                     . $templatecode . "\r\n";

    return $letterheader;
}

sub letterRecipient {
    my %param = @_;

    my $borrowerinfo = '20' . $param{'firstname'} . ' ' . $param{'surname'} . "\r\n"
                     . ' 0' . $param{'address'} . "\r\n"
                     . ' 0' . $param{'zipcode'} . ' ' . $param{'city'} . "\r\n"
                     . ' 0' . $param{'country'} . "\r\n";

   return $borrowerinfo;
}

sub toEPL {
    my %param = @_;

    my $borrower = Koha::Patrons->find( $param{'borrowernumber'} );
    my $letterdate = output_pref ( { dt => dt_from_string(), dateonly => 1 } );

    my $epl = EPLHeader       ( 'branchconfig' => $param{'branchconfig'} )

            . letterHeader    ( 'branchcode'   => $param{'branchcode'},
                                'branchconfig' => $param{'branchconfig'},
                                'subject'      => $param{'subject'},
                                'date'         => $letterdate,
                                'zipcode'      => $borrower->zipcode )

            . letterRecipient ( 'firstname'    => $borrower->firstname,
                                'surname'      => $borrower->surname,
                                'address'      => $borrower->address,
                                'zipcode'      => $borrower->zipcode,
                                'city'         => $borrower->city,
                                'country'      => $borrower->country )

            . letterBody      ( 'branchconfig' => $param{'branchconfig'},
                                'content'      => $param{'content'} );

    return $epl;
}

1;
