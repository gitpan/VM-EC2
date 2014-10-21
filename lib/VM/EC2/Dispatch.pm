package VM::EC2::Dispatch;

use strict;

use XML::Simple;
use URI::Escape;

=head1 NAME

VM::EC2::Dispatch - Create Perl objects from AWS XML requests

=head1 SYNOPSIS

  use VM::EC2;

  VM::EC2::Dispatch->add_override('DescribeRegions'=>\&mysub);

  VM::EC2::Dispatch->add_override('DescribeTags'=>'My::Type');
  
  sub mysub {
      my ($parsed_xml_object,$ec2) = @_;
      my $payload = $parsed_xml_object->{regionInfo}
      return My::Type->new($payload,$ec2);
  }

=head1 DESCRIPTION

This class handles turning the XML response to AWS requests into perl
objects. Only one method is likely to be useful to developers, the
add_override() class method. This allows you to replace the built-in
request to object mapping with your own objects.

=head2 VM::EC2::Dispatch->add_override($request_name => \&sub)
=head2 VM::EC2::Dispatch->add_override($request_name => 'Class::Name')

Before invoking a VM::EC2 request you wish to customize, call the
add_override() method with two arguments. The first argument is the
name of the request you wish to customize, such as
"DescribeVolumes". The second argument is either a code reference, or
a string containing a class name.

In the case of a code reference as the second argument, the subroutine
you provide will be invoked with two arguments consisting of the
parsed XML response and the VM::EC2 object.

In the case of a string containing a classname, the class will be
loaded if it needs to be, and then its new() method invoked as
follows:

  Your::Class->new($parsed_xml,$ec2)

Your new() method should return one or more objects.

In either case, the parsed XML response will have been passed through
XML::Simple with the options:

  $parser = XML::Simple->new(ForceArray    => ['item'],
                             KeyAttr       => ['key'],
                             SuppressEmpty => undef);
  $parsed = $parser->XMLin($raw_xml)

In general, this will give you a hash of hashes. Any tag named 'item'
will be forced to point to an array reference, and any tag named "key"
will be flattened as described in the XML::Simple documentation.

A simple way to examine the raw parsed XML is to invoke any
VM::EC2::Object's as_string method:

 my ($i) = $ec2->describe_instances;
 print $i->as_string;

This will give you a Data::Dumper representation of the XML after it
has been parsed.

=cut

my %OVERRIDE;

use constant ObjectRegistration => {
    Error             => 'VM::EC2::Error',
    DescribeInstances => sub { load_module('VM::EC2::ReservationSet');
			       my $r = VM::EC2::ReservationSet->new(@_) or return;
			       return $r->instances;
    },
    RunInstances      => sub { load_module('VM::EC2::Instance::Set');
			       my $s = VM::EC2::Instance::Set->new(@_) or return;
			       return $s->instances;
    },
    DescribeSnapshots => 'fetch_items,snapshotSet,VM::EC2::Snapshot',
    DescribeVolumes   => 'fetch_items,volumeSet,VM::EC2::Volume',
    DescribeImages    => 'fetch_items,imagesSet,VM::EC2::Image',
    DescribeRegions   => 'fetch_items,regionInfo,VM::EC2::Region',
    DescribeAvailabilityZones  => 'fetch_items,availabilityZoneInfo,VM::EC2::AvailabilityZone',
    DescribeSecurityGroups   => 'fetch_items,securityGroupInfo,VM::EC2::SecurityGroup',
    CreateSecurityGroup      => 'VM::EC2::SecurityGroup',
    DeleteSecurityGroup      => 'VM::EC2::SecurityGroup',
    AuthorizeSecurityGroupIngress  => 'boolean',
    AuthorizeSecurityGroupEgress   => 'boolean',
    RevokeSecurityGroupIngress  => 'boolean',
    RevokeSecurityGroupEgress   => 'boolean',
    DescribeTags      => 'fetch_items,tagSet,VM::EC2::Tag,nokey',
    CreateVolume      => 'VM::EC2::Volume',
    DeleteVolume      => 'boolean',
    AttachVolume      => 'VM::EC2::BlockDevice::Attachment',
    DetachVolume      => 'VM::EC2::BlockDevice::Attachment',
    CreateSnapshot    => 'VM::EC2::Snapshot',
    DeleteSnapshot    => 'boolean',
    ModifySnapshotAttribute => 'boolean',
    ResetSnapshotAttribute  => 'boolean',
    ModifyInstanceAttribute => 'boolean',
    ModifyImageAttribute    => 'boolean',
    ResetInstanceAttribute  => 'boolean',
    ResetImageAttribute     => 'boolean',
    CreateImage             => sub { 
	my ($data,$aws) = @_;
	my $image_id = $data->{imageId} or return;
	sleep 2; # wait for the thing to register
	return $aws->describe_images($image_id);
    },
    RegisterImage             => sub { 
	my ($data,$aws) = @_;
	my $image_id = $data->{imageId} or return;
	sleep 2; # wait for the thing to register
	return $aws->describe_images($image_id);
    },
    DeregisterImage      => 'boolean',
    DescribeAddresses => 'fetch_items,addressesSet,VM::EC2::ElasticAddress',
    AssociateAddress  => sub {
	my $data = shift;
	return $data->{associationId} || ($data->{return} eq 'true');
    },
    DisassociateAddress => 'boolean',
    AllocateAddress   => 'VM::EC2::ElasticAddress',
    ReleaseAddress    => 'boolean',
    CreateTags        => 'boolean',
    DeleteTags        => 'boolean',
    StartInstances       => 'fetch_items,instancesSet,VM::EC2::Instance::State::Change',
    StopInstances        => 'fetch_items,instancesSet,VM::EC2::Instance::State::Change',
    TerminateInstances   => 'fetch_items,instancesSet,VM::EC2::Instance::State::Change',
    RebootInstances      => 'boolean',
    MonitorInstances     => 'fetch_items,instancesSet,VM::EC2::Instance::MonitoringState',
    UnmonitorInstances   => 'fetch_items,instancesSet,VM::EC2::Instance::MonitoringState',
    GetConsoleOutput     => 'VM::EC2::Instance::ConsoleOutput',
    GetPasswordData      => 'VM::EC2::Instance::PasswordData',
    DescribeKeyPairs     => 'fetch_items,keySet,VM::EC2::KeyPair',
    CreateKeyPair        => 'VM::EC2::KeyPair',
    ImportKeyPair        => 'VM::EC2::KeyPair',
    DeleteKeyPair        => 'boolean',
    DescribeReservedInstancesOfferings 
	 => 'fetch_items,reservedInstancesOfferingsSet,VM::EC2::ReservedInstance::Offering',
    DescribeReservedInstances          => 'fetch_items,reservedInstancesSet,VM::EC2::ReservedInstance',
    PurchaseReservedInstancesOffering  => sub { my ($data,$ec2) = @_;
						my $ri_id = $data->{reservedInstancesId} or return;
						return $ec2->describe_reserved_instances($ri_id);
    },
};

sub new {
    my $self    = shift;
    return bless {},ref $self || $self;
}

sub add_override {
    my $self = shift;
    my ($request_name,$object_creator) = @_;
    $OVERRIDE{$request_name} = $object_creator;
}

sub response2objects {
    my $self     = shift;
    my ($response,$ec2) = @_;

    my $class    = $self->class_from_response($response) or return;
    my $content  = $response->decoded_content;

    if (ref $class eq 'CODE') {
	my $parsed = $self->new_xml_parser->XMLin($content);
	$class->($parsed,$ec2,@{$parsed}{'xmlns','requestId'});
    }
    elsif ($class =~ /^VM::EC2/) {
	load_module($class);
	my $parser   = $self->new();
	$parser->parse($content,$ec2,$class);
    } else {
	my ($method,@params) = split /,/,$class;
	return $self->$method($content,$ec2,@params);
    }
}

sub class_from_response {
    my $self     = shift;
    my $response = shift;
    my ($action) = $response->request->content =~ /Action=([^&]+)/;
    $action      = uri_unescape($action);
    return $OVERRIDE{$action} || ObjectRegistration->{$action} || 'VM::EC2::Generic';
}

sub parser { 
    my $self = shift;
    return $self->{xml_parser} ||=  $self->new_xml_parser;
}

sub parse {
    my $self    = shift;
    my ($content,$ec2,$class) = @_;
    $self       = $self->new unless ref $self;
    my $parsed  = $self->parser->XMLin($content);
    return $self->create_objects($parsed,$ec2,$class);
}

sub new_xml_parser {
    my $self  = shift;
    my $nokey = shift;
    return XML::Simple->new(ForceArray    => ['item'],
			    KeyAttr       => $nokey ? [] : ['key'],
			    SuppressEmpty => undef,
	);
}

sub fetch_one {
    my $self = shift;
    my ($content,$ec2,$class,$nokey) = @_;
    load_module($class);
    my $parser = $self->new_xml_parser($nokey);
    my $parsed = $parser->XMLin($content);
    return $class->new($parsed,$ec2,@{$parsed}{'xmlns','requestId'});
}

sub boolean {
    my $self = shift;
    my ($content,$ec2,$tag) = @_;
    my $parsed = $self->new_xml_parser()->XMLin($content);
    $tag ||= 'return';
    return $parsed->{$tag} eq 'true';
}

sub fetch_items {
    my $self = shift;
    my ($content,$ec2,$tag,$class,$nokey) = @_;
    load_module($class);
    my $parser = $self->new_xml_parser($nokey);
    my $parsed = $parser->XMLin($content);
    my $list   = $parsed->{$tag}{item} or return;
    return map {$class->new($_,$ec2,@{$parsed}{'xmlns','requestId'})} @$list;
}

sub create_objects {
    my $self   = shift;
    my ($parsed,$ec2,$class) = @_;
    return $class->new($parsed,$ec2,@{$parsed}{'xmlns','requestId'});
}

sub create_error_object {
    my $self = shift;
    my ($content,$ec2) = @_;
    my $class   = ObjectRegistration->{Error};
    eval "require $class; 1" || die $@ unless $class->can('new');
    my $parsed = $self->new_xml_parser->XMLin($content);
    return $class->new($parsed->{Errors}{Error},$ec2,@{$parsed}{'xmlns','requestId'});
}

# not a method!
sub load_module {
    my $class = shift;
    eval "require $class; 1" || die $@ unless $class->can('new');
}

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Object>
L<VM::EC2::Generic>
L<VM::EC2::BlockDevice>
L<VM::EC2::BlockDevice::Attachment>
L<VM::EC2::BlockDevice::Mapping>
L<VM::EC2::BlockDevice::Mapping::EBS>
L<VM::EC2::Error>
L<VM::EC2::Generic>
L<VM::EC2::Group>
L<VM::EC2::Image>
L<VM::EC2::Instance>
L<VM::EC2::Instance::ConsoleOutput>
L<VM::EC2::Instance::Set>
L<VM::EC2::Instance::State>
L<VM::EC2::Instance::State::Change>
L<VM::EC2::Instance::State::Reason>
L<VM::EC2::Region>
L<VM::EC2::ReservationSet>
L<VM::EC2::SecurityGroup>
L<VM::EC2::Snapshot>
L<VM::EC2::Tag>
L<VM::EC2::Volume>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

1;

