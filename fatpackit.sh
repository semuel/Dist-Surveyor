#!/bin/sh

fatpack trace bin/dist_surveyor
fatpack packlists-for `cat fatpacker.trace` > fatpacker.packlists
./process_fatpacker_packlist.pl fatpacker.packlists
fatpack tree `cat fatpacker.packlists`
(fatpack file; cat bin/dist_surveyor ) > dist_surveyor_packed.pl
rm fatpacker.trace fatpacker.packlists
