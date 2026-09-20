# Security policy

## Reporting a vulnerability

Report privately through GitHub's private vulnerability reporting on this
repository. Do not open a public issue for a vulnerability.

You should get an acknowledgement within 7 days and an assessment within 14.

Most valuable here: a weakness in the shared library, because every game image
generated from this template inherits it. The credential guard, the pinned
download path and the process matching are the three places where a flaw would
reach every server at once.

## What this repository never contains

No detail of any real deployment: no addresses, hostnames, network layout or
firewall rules, in the code, the documentation, commit messages, PR bodies or
issues. Examples use `192.168.1.50` and the documentation range
`203.0.113.0/24`.

No secret belongs here, in a string literal, in a build argument or in an
example file.

## Standard

This repository conforms to the
[Absolute engineering standard](https://github.com/abspwgm/absolute-standard).
Its answers, including its open exceptions, are in
[`.absolute/policy.yml`](.absolute/policy.yml).
