package VM::EC2::Generic;

=head1 NAME

VM::EC2::Generic - Base class for VM::EC2 objects

=head1 SYNOPSIS

  use VM::EC2;

 my $ec2 = VM::EC2->new(-access_key => 'access key id',
                      -secret_key => 'aws_secret_key',
                      -endpoint   => 'http://ec2.amazonaws.com');

 my $object = $ec2->some_method(...);

 # getting data fields
 my @field_names = $object->fields;

 # invoking data fields as methods
 my $request_id = $object->requestId;
 my $xmlns      = $object->xmlns;

 # tagging 
 my $tags = $object->tags;

 if ($tags->{Role} eq 'WebServer') {
    $object->delete_tags(Role=>undef);
    $object->add_tags(Role   => 'Web Server',
                      Status => 'development');
 }

 # get the parsed XML object as a hash
 my $hashref = $object->payload;

 # get the parsed XML object as a Data::Dumper string
 my $text = $object->as_string;

 # get the VM::EC2 object back
 my $ec2 = $object->ec2;

 # get the most recent error string
 warn $object->error_str;

=head1 DESCRIPTION

This is a common base class for objects returned from VM::EC2. It
provides a number of generic methods that are used in subclasses, but
is not intended to be used directly.

=head1 METHODS

=cut

use strict;
use Carp 'croak';
use Data::Dumper;
use VM::EC2 'tag';

our $AUTOLOAD;
$Data::Dumper::Terse++;
$Data::Dumper::Indent=1;

use overload
    '""'     => sub {my $self = shift;
		     return $self->short_name;
                  },
    fallback => 1;

sub AUTOLOAD {
    my $self = shift;
    my ($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    return if $func_name eq 'DESTROY';
    my %fields = map {$_=>1} $self->valid_fields;
    my $mixed  = VM::EC2->uncanonicalize($func_name);# mixedCase
    my $flat   = VM::EC2->canonicalize($func_name);  # underscore_style
    $flat =~ s/^-//;

    if ($mixed eq $flat) {
	return $self->{data}{$mixed} if $fields{$mixed};
	return $self->{data}{ucfirst $mixed} if $fields{ucfirst $mixed};
	croak "Can't locate object method \"$func_name\" via package \"$pack\"";
    }

    if ($func_name eq $flat && $self->can($mixed)) {
	return $self->$mixed(@_);
    } elsif ($func_name eq $mixed && $self->can($flat)) {
	return $self->$flat(@_);
    } elsif ($fields{$mixed}) {
	return $self->{data}{$mixed} if $fields{$mixed};
    } elsif ($fields{ucfirst($mixed)}) {  
	# very occasionally an API field breaks Amazon's coding 
	# conventions and starts with an uppercase
	return $self->{data}{ucfirst($mixed)};
    } else {
	croak "Can't locate object method \"$func_name\" via package \"$pack\"";
    }
}

sub can {
    my $self = shift;
    my $method = shift;

    my $can  = $self->SUPER::can($method);
    return $can if $can;
    
    my %fields = map {$_=>1} $self->valid_fields;
    return \&AUTOLOAD if $fields{$method};

    return;
}

=head2 $object = VM::EC2::Generic->new($payload,$ec2 [,$xmlns, $requestId])

Given the parsed XML generated by VM::EC2::Dispatch and the VM::EC2
object, return a new object. Two optional additional arguments provide
the seldom-needed XML namespace and ID of the request that generated
this object.

=cut

sub new {
    my $self = shift;
    @_ >= 2 or croak "Usage: $self->new(\$data,\$ec2)";
    my ($data,$ec2,$xmlns,$requestid) = @_;
    return bless {data => $data,
		  aws  => $ec2,
		  xmlns => $xmlns,
		  requestId => $requestid
    },ref $self || $self;
}

=head2 $ec2 = $object->ec2

=head2 $ec2 = $object->aws

Return the VM::EC2 object that generated this object. This method can
be called as either ec2() (preferred) or aws() (deprecated).

=cut

sub ec2 {
    my $self = shift;
    my $d    = $self->{aws};
    $self->{aws} = shift if @_;
    $d;
}

sub aws {shift->ec2}

=head2 $id = $object->primary_id  (optional method)

Resources that have unique Amazon identifiers, such as images,
instances and volumes, implement the primary_id() method to return
that identifier. Resources that do not have unique identifiers, will
throw an exception if this method is called. This method is in
addition to the resource-specific ID. For example, volumes have a
unique ID, and this ID can be fetched with either of:

  $vol->volumeId;

or

  $vol->primary_id;

=back

=head2 $xmlns = $object->xmlns

Return the XML namespace of the request that generated this object, if
any. All objects generated by direct requests on the VM::EC2 object
will return this field, but objects returned via methods calls on
these objects (objects once removed) may not.

=cut

sub xmlns     { shift->{xmlns}     }

=head2 $id = $object->requestId

Return the ID of the reuqest that generated this object, if any. All
objects generated by direct requests on the VM::EC2 object will return
this field, but objects returned via methods calls on these objects
(objects once removed) may not.

=cut

sub requestId { shift->{requestId} }

=head2 $name = $object->short_name

Return a short name for this object for use in string
interpolation. If the object has a primary_id() method, then this
returns that ID. Otherwise it returns the default Perl object name
(VM::EC2::Generic=HASH(0x99f3850). Some classes override short_name()
in order to customized information about the object. See for example
L<VM::EC2::SecurityGroup::IpPermission>.

=cut

sub short_name {
    my $self = shift;
    if ($self->can('primary_id')) {
	return $self->primary_id;
    } else {
	return overload::StrVal($self);
    }
}

=head2 $hashref = $object->payload

Return the parsed XML hashref that underlies this object. See
L<VM::EC2::Dispatch>.

=cut

sub payload { shift->{data} }


=head2 @fields = $object->fields

Return the data field names that are valid for an object of this
type. These field names correspond to tags in the XML
returned from Amazon and can then be used as method calls.

Internally, this method is called valid_fields()

=cut

sub fields    { shift->valid_fields }

sub valid_fields {
    return qw(xmlns requestId)
}

=head2 $text = $object->as_string

Return a Data::Dumper representation of the contents of this object's
payload.

=cut

sub as_string {
    my $self = shift;
    return Dumper($self->{data});
}

=head2 $hashref = $object->tags

=head2 $hashref = $object->tagSet

Return the metadata tags assigned to this resource, if any, as a
hashref. Both tags() and tagSet() work identically.

=cut

sub tags {
    my $self = shift;
    my $result = {};
    my $set  = $self->{data}{tagSet} or return $result;
    my $innerhash = $set->{item}     or return $result;
    for my $key (keys %$innerhash) {
	$result->{$key} = $innerhash->{$key}{value};
    }
    return $result;
}

sub tagSet {
    return shift->tags();
}


=head2 $boolean = $object->add_tags(Tag1=>'value1',Tag2=>'value2',...)

=head2 $boolean = $object->add_tags(\%hash)

Add one or more tags to the object. You may provide either a list of
tag/value pairs or a hashref. If no tag of the indicated name exsists
it will be created. If there is already a tag by this name, it will
be set to the provided value. The result code is true if the Amazon
resource was successfully updated.

Also see VM::EC2->add_tags() for a way of tagging multiple resources
simultaneously.

The alias add_tag() is also provided as a convenience.

=cut

sub add_tags {
    my $self = shift;
    my $taglist = ref $_[0] && ref $_[0] eq 'HASH' ? shift : {@_};
    $self->can('primary_id') or croak "You cannot tag objects of type ",ref $self;
    $self->aws->create_tags(-resource_id => $self->primary_id,
			    -tag         => $taglist);
}

sub add_tag { shift->add_tags(@_) }

=head2 $boolean = $object->delete_tags(@args)

Delete the indicated tags from the indicated resource. There are
several variants you may use:

 # delete Foo tag if it has value "bar" and Buzz tag if it has value 'bazz'
 $i->delete_tags({Foo=>'bar',Buzz=>'bazz'})  

 # same as above but using a list rather than a hashref
 $i->delete_tags(Foo=>'bar',Buzz=>'bazz')  

 # delete Foo tag if it has any value, Buzz if it has value 'bazz'
 $i->delete_tags({Foo=>undef,Buzz=>'bazz'})

 # delete Foo and Buzz tags unconditionally
 $i->delete_tags(['Foo','Buzz'])

 # delete Foo tag unconditionally
 $i->delete_tags('Foo');

Also see VM::EC2->delete_tags() for a way of deleting tags from multiple
resources simultaneously.

=cut

sub delete_tags {
    my $self = shift;
    my $taglist;

    if (ref $_[0]) {
	if (ref $_[0] eq 'HASH') {
	    $taglist = shift;
	} elsif (ref $_[0] eq 'ARRAY') {
	    $taglist = {map {$_=>undef} @{$_[0]} };
	}
    } else {
	if (@_ == 1) {
	    $taglist = {shift()=>undef};
	} else {
	    $taglist = {@_};
	}
    }

    $self->can('primary_id') or croak "You cannot delete tags from objects of type ",ref $self;
    $self->aws->delete_tags(-resource_id => $self->primary_id,
			    -tag         => $taglist);
}

sub _object_args {
    my $self = shift;
    return ($self->aws,$self->xmlns,$self->requestId);
}

=head2 $xml = $object->as_xml

Returns an XML version of the object. The object will already been
parsed by XML::Simple at this point, and so the data returned by this
method will not be identical to the XML returned by AWS.

=cut

sub as_xml {
    my $self = shift;
    XML::Simple->new->XMLout($self->payload,
			     NoAttr    => 1,
			     KeyAttr   => ['key'],
			     RootName  => 'xml',
	);
}

=head2 $value = $object->attribute('tag_name')

Returns the value of a tag in the XML returned from AWS, using a
simple heuristic. If the requested tag has a nested tag named <value>
it will return the contents of <value>. If the tag has one or more
nested tags named <item>, it will return a list of hashrefs located
within the <item> tag. Otherwise it will return the contents of
<tag_name>.

=cut

sub attribute {
    my $self = shift;
    my $attr = shift;
    my $payload = $self->payload   or return;
    my $hr      = $payload->{$attr} or return;
    return $hr->{value}   if $hr->{value};
    return @{$hr->{item}} if $hr->{item};
    return $hr;
}

=head2 $string = $object->error_str

Returns the error string for the last operation, if any, as reported
by VM::EC2.

=cut

sub error_str {
    my $self = shift;
    my $ec2  = $self->ec2 or return;
    $ec2->error_str;
}

=head2 $string = $object->error

Returns the L<VM::EC2::Error> object from the last operation, if any,
as reported by VM::EC2.

=cut

sub error {
    my $self = shift;
    my $ec2  = $self->ec2 or return;
    $ec2->error;
}

=head1 STRING OVERLOADING

This base class and its subclasses use string overloading so that the
object looks and acts like a simple string when used in a string
context (such as when printed or combined with other
strings). Typically the string corresponds to the Amazon resource ID
such as "ami-12345" and is generated by the short_name() method.

You can sort and compare the objects as if they were strings, but
despite this, object method calls work in the usual way.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Dispatch>
L<VM::EC2::Generic>
L<VM::EC2::BlockDevice>
L<VM::EC2::BlockDevice::Attachment>
L<VM::EC2::BlockDevice::Mapping>
L<VM::EC2::BlockDevice::Mapping::EBS>
L<VM::EC2::ConsoleOutput>
L<VM::EC2::Error>
L<VM::EC2::Generic>
L<VM::EC2::Group>
L<VM::EC2::Image>
L<VM::EC2::Instance>
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

