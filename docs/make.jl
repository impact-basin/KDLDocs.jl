# Build the documentation with Documenter.jl.
#
#     julia --project=docs docs/make.jl
#
# The site is built by .github/workflows/Documentation.yml and deployed to
# GitHub Pages from the repository named in `deploydocs` below.  Change the
# owner there if the mirror moves.

using Documenter
using KDLDocs

makedocs(
    sitename = "KDLDocs.jl",
    authors = "henry eshbaugh",
    modules = [KDLDocs],
    doctest = true,
    checkdocs = :exports,
    remotes = nothing,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        repolink = "https://github.com/impact-basin/KDLDocs.jl",
    ),
    pages = [
        "Home" => "index.md",
        "Usage" => "usage.md",
        "API Reference" => "api.md",
    ],
)

deploydocs(
    repo = "github.com/impact-basin/KDLDocs.jl",
    push_preview = true,
)
