# Perl module for parsing config files.
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

package XorpConfigParser;

use strict;
use warnings;
use Carp;
use Symbol qw(qualify_to_ref);

my %data;

my %fields = ( _data => \%data );

sub new {
    my $that  = shift;
    my $class = ref($that) || $that;
    my $self  = { %fields, };

    bless $self, $class;
    return $self;
}

#
# This method is used to copy nodes whose names begin with a particular string
# from one array to another.
#
# Parameters:
#
# $from		Reference to the source array
# $to		Reference to the destination array
# $name		The string with which the beginning of the node names will be matched
#
sub copy_node {
    my ( $self, $from, $to, $name ) = @_;
    if ( !defined($from) || !defined($to) || !defined($name) ) {
        return;
    }

    foreach my $node (@$from) {
        my $stringNodeNameHere = $node->{'name'};
        if ( $stringNodeNameHere =~ /^$name.*/x ) {
            foreach my $nodeCheck (@$to) {
                my $stringCheck = $nodeCheck->{'name'};
                if ( $name eq $stringCheck ) {
                    $nodeCheck->{'value'}    = $node->{'value'};
                    $nodeCheck->{'children'} = $node->{'children'};
                    $nodeCheck->{'comment'}  = $node->{'comment'};
                    $nodeCheck->{'disable'}  = $node->{'disable'};
                    return;
                }
            }
            push( @$to, $node );
        }
    }
    return;
}

#
# This method is used to create duplicate copies of multinodes with the name
# specified, and to return the new copies in a new array.
#
#  $nodes	A reference to an array of multinodes
#  $name	The name of the multinodes to copy into the new array
#
sub copy_multis {
    my ( $self, $nodes, $name ) = @_;

    return if ( !defined($nodes) || !defined($name) );

    my @multis;

    foreach my $node (@$nodes) {
        my $stringNodeNameHere = $node->{'name'};
        if ( $stringNodeNameHere =~ /$name\s(\S+)/x ) {
            my $stringNameHere = $1;
            my %multi          = (
                'name'     => $stringNameHere,
                'comment'  => $node->{'comment'},
                'value'    => $node->{'value'},
                'disable'  => $node->{'disable'},
                'children' => $node->{'children'}
            );
            push( @multis, \%multi );
        }
    }

    return @multis;
}

#
# This method is used to comment out a particular child.
#
#  $children	A reference to an array of children
#  $name	The name of the child to comment out
#  $comment	The comment string that will be included inside the comment
#
sub comment_out_child {
    my ( $self, $children, $name, $comment ) = @_;
    if ( !defined($children) || !defined($name) ) {
        return;
    }

    for ( my $i = 0 ; $i < @$children ; $i++ ) {
        my $stringNodeNameHere = @$children[$i]->{'name'};
        if ( $name eq $stringNodeNameHere ) {
            $self->comment_out_node( @$children[$i] );
            if ( defined($comment) ) {
                @$children[$i]->{'comment_out'} = $comment;
            }
        }
    }
    return;
}

#
# This method is used to comment out a particular node.
#
#  $node	A reference to the node to comment out
#
sub comment_out_node {
    my ( $self, $node ) = @_;
    if ( !defined($node) ) {
        return;
    }

    $node->{'comment_out'} = "1";
    return;
}

#
# This method is used to create a node with the path specified.  The method
# will create parent nodes as necessary.
#
#  $path	A reference to the array containing the path segments
#
sub create_node {
    my ( $self, $path ) = @_;

    my $hash = \%data;
  SEGMENT:
    foreach my $segment (@$path) {
        my $children = $hash->{'children'};

        unless ($children) {
            my @new_children;
            $hash->{'children'} = \@new_children;
            $children = \@new_children;
        }

        foreach my $child (@$children) {
            my $name = $child->{'name'};
            next unless $name;

            if ( $name eq $segment ) {
                $hash = $child;    # record insertion point
                next SEGMENT;
            }
        }

        my %new_hash = ( 'name' => $segment );

        if ( $hash != \%data ) {

            # insertion in subtree
            push @$children, \%new_hash;
        }
        else {
            # special case for insertion at top put new before version comment
            my @comments;
            while ( my $child = pop @$children ) {
                if ( $child->{'comment'} ) {
                    unshift @comments, $child;
                }
                else {
                    push @$children, $child;
                    last;
                }
            }

            push @$children, \%new_hash;
            push @$children, @comments;
        }
        $hash = \%new_hash;
    }
    return $hash;
}

#
# This method is used to delete a child node with the name specified from an array of child nodes.
#
#  $children	A reference to the array of child nodes
#  $name	The name of the child node to delete
#
sub delete_child {
    my ( $self, $children, $name ) = @_;
    return if ( !defined($children) || !defined($name) );

    for ( my $i = 0 ; $i < @$children ; $i++ ) {
        next unless defined @$children[$i];
        my $stringNodeNameHere = @$children[$i]->{'name'};
        if ( $name eq $stringNodeNameHere ) {
            @$children[$i] = undef;
        }
    }
    return;
}

#
# This method is used to return a reference to the child node
# with the name specified.
#
#  $children	A reference to an array containing the child nodes.
#  $name	The name of the child node reference to which will be returned.
#
# If the child node with the name specified is not found,
# then 'undef' is returned.
#
sub find_child {
    my ( $self, $children, $name ) = @_;
    return if ( !defined($children) || !defined($name) );

    foreach my $child (@$children) {
        return $child if ( $name eq $child->{'name'} );
    }
    return;
}

# $ref: reference to the node to be used as the starting point.
# the same as node_exists() except that the starting point is the specified
# node (instead of root).
sub node_exists_with_ref {
    my ( $self, $ref, $path ) = @_;
    my @parr = split / /, $path;
    if ( defined( $self->get_node_with_ref( $ref, \@parr ) ) ) {
        return 1;
    }
    return 0;
}

# $path: a space-delimited string representing the path to a node.
#        e.g., 'interfaces ethernet eth0'. note that the path
#        is relative from the root level.
# returns 1 if the specified node exists. otherwise returns 0.
sub node_exists {
    my ( $self, $path ) = @_;
    my @parr = split / /, $path;

    return $self->get_node( \@parr );
}

# $ref: reference to the node to be used as the starting point.
# the same as get_node() except that the starting point is the specified
# node (instead of root).
sub get_node_with_ref {
    my ( $self, $ref, $path ) = @_;
    my $hash = $ref;

  SEGMENT:
    foreach my $segment (@$path) {
        my $children = $hash->{'children'};
        return unless $children;

        foreach my $child (@$children) {
            next unless ( $child->{'name'} eq $segment );

            $hash = $child;
            next SEGMENT;
        }

        # No children matched segment
        return;
    }

    return $hash;
}

#
# This method is used to return a reference to the hash
# of the node with the path specified.
#
#  $path - reference to an array containing the path segments of the node.
#
# If the path is invalid, then undef is returned.
sub get_node {
    my ( $self, $path ) = @_;

    return $self->get_node_with_ref( $self->{_data}, $path );
}

#
# Move a subtree from one place to another in hierarchy
# Assumes both $from and $to exist
# Returns undef if no match
sub move_child {
    my ( $self, $from, $to, $name ) = @_;
    my $source = $from->{'children'};
    return unless $source;

    for ( my $i = 0 ; $i < @$source ; $i++ ) {
        my $match = @$source[$i];
        next unless $match->{'name'} eq $name;
        splice @$source, $i, 1;    # remove old list

        my $children = $to->{'children'};
        unless ($children) {
            my @new_children;
            $to->{'children'} = \@new_children;
            $children = \@new_children;
        }

        push @$children, $match;
        return $match;
    }

    return;
}

#
# This method is used to insert a comment at a particular path.
#
#  $path	A reference to an array containing the path segments to the
#               node for which the comment is to be inserted.  The comment
#               will appear above the node.
#
# If the node with the path specified does not exist, a node with empty name
# will be created for the comment.
#
sub push_comment {
    my ( $self, $path, $comment ) = @_;

    my $hash = \%data;
    foreach my $segment (@$path) {
        my $children = $hash->{'children'};
        if ( !defined($children) ) {
            my @children;
            $hash->{'children'} = \@children;
            $children = \@children;
        }

        my $child_found = 0;
        foreach my $child (@$children) {
            if ( $child->{'name'} eq $segment ) {
                $child_found = 1;
                $hash        = $child;
                last;
            }
        }

        if ( $child_found == 0 ) {
            my %new_hash = ( 'name' => $segment );
            push( @$children, \%new_hash );
            $hash = \%new_hash;
        }
    }

    my %new_comment  = ( 'comment' => $comment );
    my $childrenPush = $hash->{'children'};
    if ( !defined($childrenPush) ) {
        my @new_children;
        $hash->{'children'} = \@new_children;
        $childrenPush = \@new_children;
    }
    push( @$childrenPush, \%new_comment );
    return;
}

#
# This method is used to set the value of a particular node
#
#  $path	A reference to an array containing the path segments to the node
#  $value	String of the value to set
#
sub set_value {
    my ( $self, $path, $value ) = @_;

    my $hash = $self->create_node($path);
    if ( defined($hash) ) {
        $hash->{'value'} = $value;
    }
    return;
}

#
# This method is used to set the value of a particular node
#
#  $path	A reference to an array containing the path segments to the node
#  $value	String of the value to set
#
sub set_disable {
    my ( $self, $path ) = @_;
    my $hash = $self->create_node($path);
    if ( defined($hash) ) {
        $hash->{'disable'} = 'true';
    }
    return;
}

#
# This method is used to generate the output of the node tree in the XORP config
# file format.  The output is printed out to the currently selected handle.
#
#  $depth	Number of indents, used when this method calls itself
#               recursively, should be 0 when used.
#  $hash	A reference to the parent node, should be the roor node when
#               used.
#
sub output {
    my ( $self, $depth, $hash ) = @_;

    $self->output_to( qualify_to_ref(select), $depth, $hash );
    return;
}

#
# The same as output(), to the file handle $fh.
#
sub output_to {
    my ( $self, $fh, $depth, $hash ) = @_;

    $hash = $self->{_data} unless $hash;

    my $comment = $hash->{'comment'};
    print {$fh} '/*' . $comment . "*/\n"
      if $comment;

    my $children = $hash->{'children'};
    foreach my $child (@$children) {
        next unless $child;
        my $comment_out = $child->{'comment_out'};
        if ($comment_out) {
            print {$fh} "\n";
            print {$fh} "/*   --- $comment_out ---   */\n"
              if ( $comment_out ne "1" );
            print {$fh} "/*   --- CONFIGURATION COMMENTED OUT DURING MIGRATION BELOW ---\n";
        }

        print {$fh} "    " x $depth;
        $self->_output_node( $fh, $depth, $child );

        print {$fh} "     --- CONFIGURATION COMMENTED OUT DURING MIGRATION ABOVE ---  */\n\n"
          if ($comment_out);
    }
    return;
}

# One node of output_to(), after its indent: "name value", or the name and
# its subtree in brackets.
sub _output_node {
    my ( $self, $fh, $depth, $node ) = @_;
    my $name  = $node->{'name'};
    my $value = $node->{'value'};

    if ($value) {
        print {$fh} "$name $value\n";
        return;
    }

    my $subtree        = $node->{'children'};
    my $print_brackets = ( defined($subtree) && @$subtree > 0 )
      || ( defined($name) && $name !~ /\s/x );

    if ($name) {
        print {$fh} $print_brackets ? "$name {\n" : "$name\n";
    }

    $self->output_to( $fh, $depth + 1, $node );
    if ($print_brackets) {
        print {$fh} "    " x $depth;
        print {$fh} "}\n";
    }
    return;
}

#
# Writes the node tree to the file $path, as output() would; returns false
# if it cannot.
#
sub write_file {
    my ( $self, $path ) = @_;

    open my $fh, '>', $path or return;
    $self->output_to( $fh, 0 );
    return close $fh;
}

#
# This method is used to parse the XORP config file specified into the internal tree
# structure that the methods above process and manipulate.
#
#  $file	String of the filename to parse
#
sub parse {
    my ( $self, $file ) = @_;

    %data = ();

    open my $in, '<', $file
      or croak "Error!  Unable to open file \"$file\".  $!";
    my $contents = do { local $/ = undef; <$in> }
      // q{};
    close $in;

    # the parser's state, moved along a character at a time
    my $st = {
        contents    => $contents,
        chars       => [ split( //, $contents ) ],
        i           => 0,
        colon       => 0,                            # in the value after "name:"
        colon_quote => 0,                            # in a quoted value after "name:"
        in_quote    => 0,
        name        => q{},
        value       => undef,
        disable     => undef,                        # 'true' after "! "
        path        => [],
    };
    my $length_contents = @{ $st->{chars} };
    while ( $st->{i} < $length_contents ) {
        if ( $st->{colon} ) {
            $self->_parse_value_char($st);
        }
        else {
            $self->_parse_name_char($st);
        }
    }
    return;
}

# parse(): the character at $st->{i} and the one after it
sub _chars_at {
    my ($st) = @_;
    my $i = $st->{i};
    return ( $st->{chars}[$i], $st->{chars}[ $i + 1 ] // q{} );
}

# parse(): a character of the value after "name:"
sub _parse_value_char {
    my ( $self, $st )    = @_;
    my ( $c,    $cNext ) = _chars_at($st);

    my $value_end = 0;
    if ( $c eq '"' ) {
        $st->{value} .= $c;
        if ( $st->{colon_quote} == 1 ) {
            $value_end = 1;
        }
        else {
            $st->{colon_quote} = 1;
        }
    }
    elsif ( $c eq '\\' && $cNext eq '"' ) {
        $st->{value} .= '\\"';
        $st->{i}++;
    }
    elsif ( defined( $st->{value} )
        && ( ( length( $st->{value} ) > 0 ) || ( $c !~ /\s/x ) ) )
    {
        $st->{value} .= $c;
    }

    if ( $st->{colon_quote} == 0
        && ( $cNext eq '}' || $cNext eq ';' || $cNext =~ /\s/x ) )
    {
        $value_end = 1;
    }
    $st->{i}++;

    return if !$value_end;
    if ( length( $st->{value} // q{} ) > 0 ) {
        $self->set_value( $st->{path}, $st->{value} );
        $st->{value} = undef;
    }
    pop( @{ $st->{path} } );
    $st->{colon_quote} = 0;
    $st->{colon}       = 0;
    return;
}

# parse(): a character outside a "name:" value
sub _parse_name_char {
    my ( $self, $st )    = @_;
    my ( $c,    $cNext ) = _chars_at($st);

    return if $self->_parse_quote_or_mark( $st, $c, $cNext );

    my $in_quote = $st->{in_quote};
    if (   ( !$in_quote && $c eq '{' )
        || ( $c eq ':' && $st->{name} !~ /\s/x )
        || $c eq "\n" )
    {
        $self->_end_name( $st, $c );
    }
    elsif ( !$in_quote && $c eq '}' ) {
        pop( @{ $st->{path} } );
        $st->{name}    = q{};
        $st->{disable} = undef;
    }
    elsif (( $in_quote || $c ne ';' )
        && ( ( length( $st->{name} ) > 0 ) || ( $c !~ /\s/x ) ) )
    {
        $st->{name} .= $c;
    }
    $st->{i}++;
    return;
}

# parse(): quotes, "! " and comments; returns true if it took the character
sub _parse_quote_or_mark {
    my ( $self, $st, $c, $cNext ) = @_;

    if ( $c eq '"' ) {
        $st->{in_quote} = $st->{in_quote} ? 0 : 1;
        $st->{name} .= '"';
        $st->{i}++;
        return 1;
    }
    if ( $c eq '\\' && $cNext eq '"' ) {
        $st->{name} .= '\\"';
        $st->{i} += 2;
        return 1;
    }
    return 0 if $st->{in_quote};

    if ( $c eq '!' && $cNext eq ' ' ) {
        $st->{disable} = 'true';
        $st->{i} += 2;
        return 1;
    }
    if ( $c eq '/' && $cNext eq '*' ) {
        my $i            = $st->{i};
        my $comment_text = q{};
        my $comment_end  = index( $st->{contents}, '*/', $i + 2 );
        if ( $comment_end == -1 ) {
            $comment_text = substr( $st->{contents}, $i + 2 );
        }
        else {
            $comment_text = substr( $st->{contents}, $i + 2, $comment_end - $i - 2 );
            $st->{i} = $comment_end + 2;
        }
        $self->push_comment( $st->{path}, $comment_text );
        return 1;
    }
    return 0;
}

# parse(): the end of a node name, at "{", "name:" or the end of a line
sub _end_name {
    my ( $self, $st, $c ) = @_;

    $st->{name} =~ s/^\s+|\s$//gx;
    return if length( $st->{name} ) == 0;

    push( @{ $st->{path} }, $st->{name} );
    if ( defined $st->{disable} && $st->{disable} eq 'true' ) {
        $self->set_disable( $st->{path} );
        $st->{disable} = undef;
    }
    $self->set_value( $st->{path}, $st->{value} );
    $st->{name} = q{};

    if ( $c eq "\n" ) {
        pop( @{ $st->{path} } );
    }
    if ( $c eq ':' ) {
        $st->{colon} = 1;
    }
    return;
}

1;
