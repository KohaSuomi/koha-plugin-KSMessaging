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
use XML::LibXML;
use HTML::Template;

## Resolve the plugin Templates directory from the installed bundle.  The
## module lives in <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/Modules/
## Deliver/, so the plugin root (and its Templates/ dir) is two directories up.
sub _template_dir {
    my $module_file = $INC{'Koha/Plugin/Fi/KohaSuomi/KSMessaging/Modules/Deliver/DispatchXML.pm'}
        || rel2abs(__FILE__);
    return catdir( dirname( rel2abs($module_file) ), '..', '..', 'Templates' );
}

## The dispatch XML is built from a template that does no escaping of its own,
## so every value that ends up in one of its attributes is escaped here.  The
## scratch document is created without an encoding on purpose: libxml2 then
## writes everything outside ASCII as a numeric character reference, which
## survives the iso-8859-1 declaration of the template instead of having to be
## encoded into it.
my $escape_document = XML::LibXML::Document->new( '1.0' );

sub _escape_value {
    my ($value) = @_;
    return '' unless defined $value;

    # Characters XML 1.0 does not allow are dropped by libxml2, which also
    # complains about them on STDERR. Drop them here instead, quietly.
    $value =~ s/[^\x09\x0A\x0D\x20-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]//g;

    # A text node would leave a double quote alone, which the attributes of
    # the template cannot take. An attribute escapes &, <, > and ".
    my $element = $escape_document->createElement('value');
    $element->setAttribute( 'value', $value );
    my ($escaped) = $element->toString =~ m{value="(.*)"}s;

    return defined $escaped ? $escaped : '';
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

       $xmlTemplate->param( SENDERID     => _escape_value( $sender{'senderId'} ) );
       $xmlTemplate->param( CONTACT      => _escape_value( $sender{'contact'} ) );
       $xmlTemplate->param( CUSTOMERID   => _escape_value( $sender{'customerId'} ) );
       $xmlTemplate->param( CUSTOMERPASS => _escape_value( $sender{'customerPass'} ) );
       $xmlTemplate->param( OVTID        => _escape_value( $sender{'ovtId'} ) );

       $xmlTemplate->param( SSN          => _escape_value( $param{'SSN'} ) );
       $xmlTemplate->param( NAME         => _escape_value( $borrower->firstname ) );
       $xmlTemplate->param( SURNAME      => _escape_value( $borrower->surname ) );
       $xmlTemplate->param( ADDRESS1     => _escape_value( $borrower->address ) );
       $xmlTemplate->param( ZIPCODE      => _escape_value( $borrower->zipcode ) );
       $xmlTemplate->param( CITY         => _escape_value( $borrower->city ) );

       $xmlTemplate->param( LETTERID     => _escape_value( $param{'letterid'} ) );
       $xmlTemplate->param( SUBJECT      => _escape_value( $param{'subject'} ) );
       $xmlTemplate->param( TOTALPAGES   => _escape_value( $param{'totalpages'} ) );

       $xmlTemplate->param( EXFILENAME   => _escape_value( $param{'filename'}) );

    return $xmlTemplate->output;
}

1;