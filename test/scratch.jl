using KDL

txt = """ ui {
    pane_frames {
        hide_session_name #true
    }
}
"""

txt = """
    ui foo = (bool)#true -bar { 
        baz abc = def {
            qux
        }
    }
"""
KDL.g(txt) |> KDL.kdl

g = KDL.g(txt)
KDL.kdl(g)
