from . import lod, vmat, vmod

def register():
    from . import props, ui, ops
    props.register()
    ui.register()
    ops.register()


def unregister():
    from . import props, ui, ops
    ops.unregister()
    ui.unregister()
    props.unregister()
