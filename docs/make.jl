# Reminder: to build, run
#     julia --project=docs docs/make.jl

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
        "API Reference" => "api.md",
    ],
)

deploydocs(
    repo = "github.com/impact-basin/KDLDocs.jl",
    push_preview = true,
)
