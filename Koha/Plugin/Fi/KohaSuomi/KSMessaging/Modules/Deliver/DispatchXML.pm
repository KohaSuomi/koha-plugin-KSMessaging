package Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::DispatchXML;
use warnings;
use strict;
use utf8;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(DispatchXML);

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile catdir rel2abs);

use Koha::Patrons;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;

use Encode;
use XML::Simple;
use HTML::Template;

## Resolve the plugin Templates directory from the installed bundle.  The
## module lives in <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/Modules/
## Deliver/, so the plugin root is four directories up.
sub _template_dir {
    my $module_file = $INC{'Koha/Plugin/Fi/KohaSuomi/KSMessaging/Modules/Deliver/DispatchXML.pm'}
        || rel2abs(__FILE__);
    return catdir( dirname( rel2abs($module_file) ), '..', '..', '..', '..', 'Templates' );
}

sub GetDispatcherConfig {
    my %param = @_;
    my %config;
    my $config = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new(
        { interface => $param{'interface'}, branch => $param{'branchconfig'} }
    );
    $config{'contact'}      = $config->contact;
    $config{'customerId'}   = $config->getIPostConfig->{customerid};
    $config{'customerPass'} = $config->getIPostConfig->{customerpass};
    $config{'ovtId'}        = $config->getIPostConfig->{ovtid};
    $config{'senderId'}     = $config->getIPostConfig->{senderid};
    return %config;
}

sub DispatchXML {
    my %param = @_;
    my %sender = GetDispatcherConfig( 'interface' => $param{'interface'}, 'branchconfig' => $param{'branchconfig'} );
    my $borrower = Koha::Patrons->find( $param{'borrowernumber'} );

    my $xmlTemplate = HTML::Template->new( filename => catfile( _template_dir(), 'DispatchXML.tmpl' ) );

       $xmlTemplate->param( SENDERID     => $sender{'senderId'} );
       $xmlTemplate->param( CONTACT      => $sender{'contact'} );
       $xmlTemplate->param( CUSTOMERID   => $sender{'customerId'} );
       $xmlTemplate->param( CUSTOMERPASS => $sender{'customerPass'} );
       $xmlTemplate->param( OVTID        => $sender{'ovtId'} );

       $xmlTemplate->param( SSN          => XML::Simple->new()->escape_value( $param{'SSN'} ) );
       $xmlTemplate->param( NAME         => XML::Simple->new()->escape_value( $borrower->firstname ) );
       $xmlTemplate->param( SURNAME      => XML::Simple->new()->escape_value( $borrower->surname ) );
       $xmlTemplate->param( ADDRESS1     => XML::Simple->new()->escape_value( $borrower->address ) );
       $xmlTemplate->param( ZIPCODE      => XML::Simple->new()->escape_value( $borrower->zipcode ) );
       $xmlTemplate->param( CITY         => XML::Simple->new()->escape_value( $borrower->city ) );

       $xmlTemplate->param( LETTERID     => $param{'letterid'} );
       $xmlTemplate->param( SUBJECT      => $param{'subject'} );
       $xmlTemplate->param( TOTALPAGES   => $param{'totalpages'} );

       $xmlTemplate->param( EXFILENAME   => $param{'filename'});

    return $xmlTemplate->output;
}

1;