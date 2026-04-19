<div align="center">
  <img src="include\800x600.logo.png" alt="VPDLX Logo" width="400" />
</div>

<br />

***

Current Version: v1.00.00 <br>
Current Build: 202604.017 <br>
Release-Type: __experimental__ <br>
<br>
Date of Birth: 2026-04-15 <br>


***

The PowerShell Module `local.httpserver` provides a lightweight and easy to use HTTP Server that runs silently in the background (after it has been startet). This Module is a bit different to normal PowerShell Modules. It is a complete Standalone Package that includes everything you need to start right from scratch. All you need to do is, to edit the `module.conf` (you'll find it inside the Module `.\include\module.conf`). But let's start from the Beginning ...

***

## Why local.httpserver ?

Unfortunately I had some issues in one of my other PowerShell Projects (PowerEdge). Part of this project is, to serve local stored SPAs independently from any other dependency. You simply use PowerEdge for running your WebApps inside PowerShell. But somehow I ran in several scope- and race-issues, that couldn't be fixed easily. So I decided to try a different way for PowerEdge. And this is, where `local.httpserver` was born.

## What is local.httpserver ?

`local.httpserver` aims to be a lightweight, easy to use, stable and portable HTTP Server that helps you, serving everything between a normal Website (with HTML/CSS and JavaScript) or a modern Single-Page-Application that uses Frameworks such as Angular, React or Vue (to name just a few). It supports several MimeTypes (can be configured easily), Routing, and many more features. You can _"talk"_ to `local.httpserver` in two differrent ways. Due to `local.httpserver` is already a HTTP-Listener, it is configured to _"listen"_ to special config-routes (might be the easiest way in most cases, cause you can simply handle `loca.http.server` from any Browser by passing a special config-route as URL). The other option, `local.httpserver` supports is __Named Pipes__. With __Named Pipes__ you can _"contact"_ `local.httpserver` from inside another PowerShell Script (for example). Or you can write your own script for _"talking"_ to `local.httpserver`