ruby-http-session
=================

Partial port of Python ROSRS_Session code to Ruby.

[This project [8]][ref8] is intended to provide a Ruby-callable API for [myExperiment [9]][ref9] to access [Research Objects [1]][ref1], [[2]][ref2] stored in RODL, using the [ROSRS API [3]][ref3].  The functions provided closely follow the ROSRS API specification.  The code is based on an implementation in Python used by the RO_Manager utility; a full implementat ROSRS test suite can be found in the [GitHub `wf4ever/ro-manager` project [7]][ref7].

[ref1]: http://www.wf4ever-project.org/@@FIXME "(cf. @@ref wf4ever wiki - ROs)"

[ref2]: http://github.org/@@FIXME "@@ref github RO model doc"

[ref3]: http://www.wf4ever-project.org/@@FIXME "wf4ever wiki ROSRS API (v6)"

[ref7]: http://github.org/@@FIXME "Python ROSRS_Session in RO Manager"
 
[ref8]: http://github.org/@@FIXME "ruby-http-session project, or successor"

[ref9]: http://myexperiment.org/@@FIXME "myExperiment"


## Contents

@@TODO: add links

* Contents
* Package structure
* API calling conventions
* A simple example
* Development setup
* URIs
* Further work
* References


## Package structure

Key functions are currently contained in four files:

* `src/rosrs_session.rb`
* `src/rdf_graph.rb`
* `src/namespaces.rb`
* `src/test_rosrs_session`

The main functions provided by this package are in `rosrs_session`.  This module provides a class whose instances manage a session with a specified ROSRS service endpoint.  A service URI is provided when an instance is created, and is used as a base URI for accessing ROs and other resources using relative URI references.  Any attempt to access a resource on a different host or post is rejected.

Module `rdf_graph` implements a simplified interface to the [Ruby RDF library [4]][ref4], handling parsing of RDF from strings, serialization to strings and simplified search and access to individual triples.  Most of the functions provided are quite trivial; the module is intended to provide (a) a distillation of knowledge about how to perform desired functions using the RDF and associated libraries, and (b) a shim layer for adapting between different conventions used by the RDF libraries and the `rosrs_session` library.  The [Raptor library [5]][ref5] and its [Ruby RDF interface[6]][ref6] are used for RDF/XML parsing and serialization.

[ref4]: http://www.ruby-zzz.org/ "Ruby RDF library"

[ref5]: http://raptor.zzz.org/ "Raptor library"

[ref6]: http://www.ruby-zzz.org/ "Ruby RDF library interface to Raptor"

Module `namespaces` provides definitions of URIs for namespaces and namespace terms used in RDF graphs.  These are in similar form to the namespaces provided by the RDF library, but recognized terms are predeclared to that spelling mistakes can be detected.

Module `test_rosrs_session` is a test suite for all the above.  It serves to provide regression testing for implemented functions, and also to provide examples of how the various ROSRS API functions provided can be accessed.


## API calling conventions

Many API functions have a small number of mandatory parameters which are provided as normal positional parameters, and a (possibly larger) number of optional keyword parameters that are provided as a Ruby hash.  The Ruby calling convention of collecting multiple `key => value` parameter expressions into a single has is used.

Return values are generally in the form of an array, which can be used with parallel assignment for easy access to the return values.

Example:

    code, reason, headers, body = rosrs.doRequest("POST", rouri,
        :body   => data
        :ctype  => "text/plain"
        :accept => "application/rdf+xml"
        :headers    => reqheaders)

Note that, when calling the `rosrs_session.doRequest` and similar methods, additional header fields are provided in a dictionary that is keyed by strings, not symbols; e.g.

    reqheaders   = {
        "slug"    => name
        }


## A simple example

Here is a flavour of how the `rosrs_session` module may be used:

    # Create an ROSRS session
    rosrs = ROSRS_Session.new(
        "http://sandbox.wf4ever-project.org/rodl/ROs/", 
        "47d5423c-b507-4e1c-8")

    # Create a new RO
    code, reason, rouri, manifest = @rosrs.createRO("Test-RO-name",
        "Test RO for ROSRS_Session", "TestROSRS_Session.py", "2012-09-28")
    if code != 201
        raise "Failed to create new RO: "+reason
    end

    # Aggregate a resource into the new RO
    res_body = %q(
        New resource body
        )
    options = { :body => res_body, :ctype => "text/plain" }

    # Create and aggregate "internal" resource in new RO
    code, reason, proxyuri, resourceuri = rosrs.aggregateResourceInt(
        rouri, "data/test_resource",
        :body => res_body,
        :ctype => "text/plain")
    if code != 201
        raise "Failed to create new resource: "+reason

    # When finished, close session
    rosrs.close


## Development setup

Development has been performed using Ruby 1.8.7 on Ubuntu Linux 10.04 and 12.04.  The code uses `rubygems`, `rdf` and `rdf-raptor` libraries beyond the standard Ruby libraries.

The `rdf-raptor` Ruby library uses the Ubuntu `raptor-util` and `libraptor-dev` packages.  NOTE: the Ruby RDF documentation does not mention `libraptor-dev`, but I found that without this the RDF libraries would not work for parsing and serializing RDF/XML.

Once the environment is set up, I find the following statements are sufficient include the required libraries:

    require "./rosrs_session"
    require "./namespaces"

@@Is there a way to include the current working directory on Ruby's library search path?  I fear this may not work if a program is run from other than the directory containing the ROSRS library code.


## URIs

Be aware that the standard Ruby library provides a URI class, and that the RDF library provides a different, incompatible URI class:

    # Standard Ruby library URI:
    uri1 = URI("http://example.com/")
    
    # URI class used by RDF library:
    uri2 = RDF::URI("http://example.com")

These URIs are not equivalent, and are not even directly comparable.

Currently, the HTTP handling code uses the standard Ruby library URIs, and the RDF handling code uses URIs provided by the RDF library.  The `namespaces` module returns `RDF::URI` values.

I'm not currently sure if this will prove to cause problems.  Take care when dereferencing URIs obtained from RDF.


## Further work

At the time of writing this, the code is very much a work in progress.  Some of the things possibly yet to-do include:

* Fork project into the wf4ever organization.  Rename to rosrs_session.
* Complete the APi functions
* Work out strategy for dealing with different URI classes.
* When creating an RO, use the supplied RO information to create some initial annotations (similar to RO Manager)?
* Refactor `rosrs_session.rb` to separate out `http_session`
* May want to investigate "streaming" RDF data between HTTP and RDF libraries, or using RDF reader/writer classes, rather than transferring via strings.  Currently, I assume the RDF is small enough that this doesn't matter.
* Add query capability to rdf_graph if required.
* Refactor test suite per tested module (may require simple HTTP server setup if HTTP factored out as above)
* Move test suite to separate directory per Ruby conventions?


## References

[[1] Wf4Ever Research Object description and notes][ref1]

[[2] Research Object model specification][ref2]

[[3] Wf4ever ROSRS API (v6)][ref3]

[[4] Ruby RDF library `rdf`][ref4]

[[5] Raptor RDF library][ref5]

[[6] Ruby RDF library `rdf-raptor` Raptor interface][ref6]

[[7] Python ROSRS_Session in RO Manager][ref7]
 
[[8] ruby-http-session project, or successor][ref8]

[[9] myExperiment][ref9]

