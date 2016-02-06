use NativeCall;

=begin pod

=head1 Inline::Scheme::Guile

C<Inline::Scheme::Guile> is a Perl 6 binding to GNU Guile Scheme.

=head1 Synopsis

    use Inline::Scheme::Guile;

    say "Scheme says 3 + 4 is " ~ Inline::Scheme::Guile.new.run('(+ 3 4)');

=head1 Documentation

You obviously need to have Guile Scheme (L<https://www.gnu.org/software/guile/manual/guile.html>)
installed in order for this module to work. At some point an L<Alien::> package
may be created to help this process. I'd prefer to have a proper repository
but that would be even more yak shaving.

You can pass any Scheme code you like to the running Guile compiler, and it
will respond with the return value(s) from the result of executing that
expression. For a full list of object types, it's probably best to look at the
test suite, but here's a brief summary of the important types:

  =item nil

  Unsurprisingly, maps to the Nil object in Perl 6.

  =item #f

  Maps to False in Perl 6.

  =item #t

  Maps to True

  =item Integers

  Those that fit into int32 map onto a regular Int in Perl 6.
  More research is needed for wider types as of this writing.

  =item Rationals

  Map onto a Perl 6 rational, with a denominator and numerator part.

  =item Complex numbers

  Map onto a Perl 6 complex value, with a real and imaginary part.

  =item Strings

  Map to the Str type.

  =item Symbols ('foo)

  Map onto the (somewhat unwieldy) L<Inline::Scheme::Guile::Symbol> type.
  These have simply a C<:name('foo')> attribute.

  =item Keywords (#:foo)

  Map onto the (somewhat unwieldy) L<Inline::Scheme::Guile::Keyword> type.
  These have simply a C<:name('foo')> attribute.

  =item List ('(1 2 3))

  Map onto an array reference. See below about multiple-value returns to see
  why this was chosen.

  =item Vector (#(1 2 3))

  Map onto the (somewhat unwieldy) L<Inline::Scheme::Guile::Vector> type.
  These have a C<:values(1,2,3)> attribute storing the values in the vector.

Scheme functions can return a single value, or more than one value. This is not
the same as a Scheme function returning a list of values. For instance:

C<$g.run('3')> returns just the value C<3>.

C<$g.run('(+ 3 4)')> returns just the value C<7>.

C<$g.run( q{'(3 4)} )> returns a list B<reference> C<[3, 4]>.

C<$g.run( q{(values 3 4)} )> returns two values, C<(3, 4)>.

Multiple-value return is the main reason why lists are array references, rather
than lists in and of themselves. Also, sometimes (most of the time (no, really))
lists are nested, and the inner layer would have to be a list reference anyway,
so for consistency's sake all lists are considered references.

=end pod

constant VECTOR_START  = -256;
constant VECTOR_END    = -255;

constant UNKNOWN_TYPE  = -2;
constant VOID          = -1;
constant ZERO          = 0;
constant TYPE_NIL      = 1;
constant TYPE_BOOL     = 2;
constant TYPE_INTEGER  = 3;
constant TYPE_STRING   = 4;
constant TYPE_DOUBLE   = 5;
constant TYPE_RATIONAL = 6;
constant TYPE_COMPLEX  = 7;
constant TYPE_SYMBOL   = 8;
constant TYPE_KEYWORD  = 9;

class Inline::Scheme::Guile::Symbol { has Str $.name }
class Inline::Scheme::Guile::Keyword { has Str $.name }
class Inline::Scheme::Guile::Vector { has @.value }

class Inline::Scheme::Guile::AltDouble is repr('CStruct')
	{
	has num64 $.real_part;
	has num64 $.imag_part;
	}

class Inline::Scheme::Guile::AltType is repr('CUnion')
	{
	has long $.int_content;
	has num64 $.double_content;
	has Str  $.string_content;
	HAS Inline::Scheme::Guile::AltDouble $.complex_content;
	}

class Inline::Scheme::Guile::ConsCell is repr('CStruct')
	{
	has int32 $.type;
	HAS Inline::Scheme::Guile::AltType $.content;
	}

class Inline::Scheme::Guile
	{
	sub native(Sub $sub)
		{
		my Str $path = %?RESOURCES<libraries/guile-helper>.Str;
		die "unable to find libguile-helper library"
			unless $path;
		trait_mod:<is>($sub, :native($path));
		}

	sub _dump( Str $expression ) { ... }
		native(&_dump);

	method _dump( Str $expression )
		{
		say "Asserting '$expression'";
		_dump( $expression );
		}

	method _push_value( $state, $content )
		{
		if $state.<vector-depth>
			{
			$state.<stuff>[*-1].value.push( $content );
			}
		else
			{
			$state.<stuff>.push( $content );
			}
		}

	method _push_cell( $cell, $state )
		{
		CATCH
			{
			warn "Don't die in callback, warn instead.\n";
			warn $_;
			}
		my $type = $cell.deref.type;
		given $type
			{
			when VECTOR_START
				{
				$state.<vector-depth>++;
				$state.<stuff>.push(
				  Inline::Scheme::Guile::Vector.new );
				}

			when VECTOR_START
				{
				$state.<vector-depth>--;
				}

			when TYPE_KEYWORD
				{
				my $content = $cell.deref.content;
				$state.<stuff>.push(
				  Inline::Scheme::Guile::Keyword.new(
				    :name($content.string_content) ) );
				}

			when TYPE_SYMBOL
				{
				my $content = $cell.deref.content;
#				$state.<stuff>.push(
self._push_value( $state,
				  Inline::Scheme::Guile::Symbol.new(
				    :name($content.string_content) ) );
				}

			when TYPE_STRING
				{
				my $content = $cell.deref.content;
				my $string = $content.string_content;
				self._push_value( $state, $string );
				}

			when TYPE_COMPLEX
				{
				my $content = $cell.deref.content;
				my $complex = $content.complex_content;
				self._push_value( $state,
				  $complex.real_part +
				  ( $complex.imag_part * i ) );
				}

			when TYPE_RATIONAL
				{
				my $content = $cell.deref.content;
				my $rational = $content.rational_content;
				$state.<stuff>.push(
				  $rational.numerator_part /
				  $rational.denominator_part );
				}

			when TYPE_DOUBLE
				{
				my $content = $cell.deref.content;
				my $double  = $content.double_content;
				self._push_value( $state, $double );
				}

			when TYPE_INTEGER
				{
				my $content = $cell.deref.content;
				my $int     = $content.int_content;
				self._push_value( $state, $int );
				}

			when TYPE_BOOL
				{
				my $content = $cell.deref.content;
				self._push_value(
				  $state,
				  $content.int_content == 1 ?? True !! False );
				}

			when TYPE_NIL { self._push_value( $state, Nil ) }

			# Don't do anything in this case.
			when VOID { }

			when UNKNOWN_TYPE { warn "Unknown type caught\n" }
			}
		}

	sub run( Str $expression,
		 &marshal_guile (Pointer[Inline::Scheme::Guile::ConsCell]) )
		   { ... }
		native(&run);

	method run( Str $expression )
		{
		my @stuff;
		my $vector-depth = 0;
		my $state = { vector-depth => 0 };
		$state.<stuff> := @stuff;
		my $ref = sub ( Pointer[Inline::Scheme::Guile::ConsCell] $cell )
			{
			self._push_cell( $cell, $state );
			}
		run( $expression, $ref );
		return @stuff;
		}
	}
