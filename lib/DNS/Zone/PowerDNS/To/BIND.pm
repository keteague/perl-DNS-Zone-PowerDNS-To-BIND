package DNS::Zone::PowerDNS::To::BIND;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(
                       gen_bind_zone_from_powerdns_db
               );

our %SPEC;

# XXX
sub _encode_txt {
    my $text = shift;
    qq("$text");
}

$SPEC{gen_bind_zone_from_powerdns_db} = {
    v => 1.1,
    summary => 'Generate BIND zone configuration from '.
        'information in PowerDNS database',
    args => {
        db_dsn => {
            schema => 'str*',
            tags => ['category:database'],
            default => 'DBI:mysql:database=pdns',
        },
        db_user => {
            schema => 'str*',
            tags => ['category:database'],
        },
        db_password => {
            schema => 'str*',
            tags => ['category:database'],
        },
        domain => {
            schema => ['net::hostname*'], # XXX domainname
            req => 1,
            pos => 0,
        },
        master_host => {
            schema => ['net::hostname*'],
            req => 1,
            pos => 1,
        },
    },
    result_naked => 1,
};
sub gen_bind_zone_from_powerdns_db {
    my %args = @_;
    my $domain = $args{domain};

    require DBIx::Connect::Any;
    my $dbh = DBIx::Connect::Any->connect(
        $args{db_dsn}, $args{db_user}, $args{db_password}, {RaiseError=>1});

    my $sth_sel_domain = $dbh->prepare("SELECT * FROM domains WHERE name=?");
    $sth_sel_domain->execute($domain);
    my $domain_rec = $sth_sel_domain->fetchrow_hashref
        or die "No such domain in the database: '$domain'";

    my @res;
    push @res, '; generated from PowerDNS database on '.scalar(gmtime)." UTC\n";

    my $sth_sel_soa_record = $dbh->prepare("SELECT * FROM records WHERE domain_id=? AND disabled=0 AND type='SOA'");
    $sth_sel_soa_record->execute($domain_rec->{id});
    my $soa_rec = $sth_sel_soa_record->fetchrow_hashref
        or die "Domain '$domain' does not have SOA record";
    push @res, '$TTL ', $soa_rec->{ttl}, "\n";
    $soa_rec->{content} =~ s/(\S+)(\s+)(\S+)(\s+)(.+)/$1.$2$3.$4($5)/;
    push @res, "\@ IN $soa_rec->{ttl} SOA $soa_rec->{content};\n";

    my $sth_sel_record = $dbh->prepare("SELECT * FROM records WHERE domain_id=? AND disabled=0 ORDER BY id");
    $sth_sel_record->execute($domain_rec->{id});
    while (my $rec = $sth_sel_record->fetchrow_hashref) {
        my $type = $rec->{type};
        next if $type eq 'SOA';
        my $name = $rec->{name};
        $name =~ s/\.?\Q$domain\E\z//;
        push @res, "$name ", ($rec->{ttl} ? "$rec->{ttl} ":""), "IN ";
        if ($type eq 'A') {
            push @res, "A $rec->{content}\n";
        } elsif ($type eq 'CNAME') {
            push @res, "CNAME $rec->{content}.\n";
        } elsif ($type eq 'MX') {
            push @res, "MX $rec->{prio} $rec->{content}.\n";
        } elsif ($type eq 'NS') {
            push @res, "NS $rec->{content}.\n";
        } elsif ($type eq 'TXT') {
            push @res, "TXT ", _encode_txt($rec->{content}), "\n";
        } else {
            die "Can't dump record with type $type";
        }
    }

    join "", @res;
}

1;
# ABSTRACT:

=head1 SYNOPSIS

 use DNS::Zone::PowerDNS::To::BIND qw(gen_bind_zone_from_powerdns_db);

 say gen_bind_zone_from_powerdns_db(
     db_dsn => 'dbi:mysql:database=pdns',
     domain => 'example.com',
     master_host => 'dns1.example.com',
 );

will output something like:

 $TTL 300
 @ IN 300 SOA ns1.example.com. hostmaster.example.org. (
   2019072401 ;serial
   7200 ;refresh
   1800 ;retry
   12009600 ;expire
   300 ;ttl
   )
  IN NS ns1.example.com.
  IN NS ns2.example.com.
  IN A 1.2.3.4
 www IN CNAME @


=head1 SEE ALSO

L<Sah::Schemas::DNS>

L<DNS::Zone::Struct::To::BIND>
