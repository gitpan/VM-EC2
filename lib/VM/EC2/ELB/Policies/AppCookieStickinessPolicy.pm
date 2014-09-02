package VM::EC2::ELB::Policies::AppCookieStickinessPolicy;

=head1 NAME

VM::EC2::ELB:Policies::AppCookieStickinessPolicy - Object describing 
an Application Cookie Stickiness Policy

=head1 SYNOPSIS

  use VM::EC2;

  $ec2          = VM::EC2->new(...);
  $lb           = $ec2->describe_load_balancers('my-lb');
  $p            = $lb->Policies();

  @app_policies = $p->AppCookieStickinessPolicies();

=head1 DESCRIPTION

This object is used to describe the AppCookieStickinessPolicy data type.

=head1 METHODS

The following object methods are supported:
 
 PolicyName  -- The name of the policy
 CookieName  -- The name of the application cookie for the policy

=head1 STRING OVERLOADING

In string context, the object will return the policy name.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::ELB>
L<VM::EC2::ELB::Policies>

=head1 AUTHOR

Lance Kinley E<lt>lkinley@loyaltymethods.comE<gt>.

Copyright (c) 2012 Loyalty Methods, Inc.

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'VM::EC2::Generic';

use overload
    '""'     => sub { shift->PolicyName },
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(CookieName PolicyName);
}

1;
