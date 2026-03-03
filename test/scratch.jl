using KDL

txt = """ ui {
    pane_frames {
        hide_session_name #true
    }
}
"""

txt = """
    ui foo = #true bar { 
        baz abc = def {
            qux
        }
    }
"""
data = KDL.syntax(txt) |> KDL.semantics

g = KDL.g(txt)
KDL.kdl(g)
