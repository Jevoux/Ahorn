eventMouse = Union{Gtk.GdkEventButton, Gtk.GdkEventMotion, Gtk.GdkEventCrossing}
eventKey = Gtk.GdkEventKey

macro progress(e::Expr, msg, dialog)
    return quote
        if !disableLoadingScreen && $dialog !== nothing
            set_gtk_property!($dialog, :secondary_text, $msg)
            LoadingSpinner.animate($dialog)
            waitForIdle()
        end

        $e
    end |> esc
end

# Stupid hack to make @gtktype macro work from here
function GtkType(name::Symbol)
    expr = Meta.parse("@gtktype $name")
    Base.eval(Gtk, expr)

    return getfield(Gtk, name)
end

# Radio Menu Item

GtkType(:GtkRadioMenuItem)

function RadioMenuItem(name::String, group::Any=C_NULL)
    return Gtk.GtkRadioMenuItem(
        ccall((:gtk_radio_menu_item_new_with_label, Gtk.libgtk), Ptr{GObject}, (Ptr{Nothing}, Ptr{UInt8}), group, name)
    )
end

function RadioMenuItem(name::String, widget::Gtk.GtkRadioMenuItem)
    return Gtk.GtkRadioMenuItem(
        ccall((:gtk_radio_menu_item_new_with_label_from_widget, Gtk.libgtk), Ptr{GObject}, (Ptr{GObject}, Ptr{UInt8}), widget, name)
    )
end

function connectRadioGroupSignal(func::Function, radios::Array{Gtk.GtkRadioMenuItem, 1}; onlyCallbackActive::Bool=true)
    for radio in radios
        @guarded signal_connect(radio, "toggled") do widget
            active = get_gtk_property(widget, :active, Bool)
            index = findfirst(isequal(widget), radios)

            if active && onlyCallbackActive || !onlyCallbackActive
                func(index)
            end
        end
    end
end

function connectRadioGroupSignal(funcs::Array{Function, 1}, radios::Array{Gtk.GtkRadioMenuItem, 1}; onlyCallbackActive::Bool=true)
    for radio in radios
        @guarded signal_connect(radio, "toggled") do widget
            active = get_gtk_property(widget, :active, Bool)
            index = findfirst(isequal(widget), radios)

            if active && onlyCallbackActive || !onlyCallbackActive
                funcs[index]()
            end
        end
    end
end


# Image Menu Item

GtkType(:GtkImageMenuItem)

function setImageMenuItemIcon!(item::Gtk.GtkImageMenuItem, image::Gtk.GtkImage)
    ccall((:gtk_image_menu_item_set_image, Gtk.libgtk), Ptr{Nothing}, (Ptr{GObject}, Ptr{GObject}), item, image)
end

function ImageMenuItem(name::String)
    return Gtk.GtkImageMenuItem(
        ccall((:gtk_image_menu_item_new_with_label , Gtk.libgtk), Ptr{GObject}, (Ptr{UInt8},), name)
    )
end

function ImageMenuItem(name::String, image::Gtk.GtkImage)
    item = ImageMenuItem(name)
    setImageMenuItemIcon!(item, image)

    return item
end


# Check Menu Item

GtkType(:GtkCheckMenuItem)

function CheckMenuItem(name::String, group::Any=C_NULL)
    return Gtk.GtkCheckMenuItem(
        ccall((:gtk_check_menu_item_new_with_label, Gtk.libgtk), Ptr{GObject}, (Ptr{UInt8},), name)
    )
end

# Window Cursor

# Since our objects are kinda badly thrown together we need to cache them to prevent duplication errors
cursorCache = Dict{Tuple{Gtk.GtkWindow, Ptr{GObject}}, Gtk.GObject}()

# https://developer.gnome.org/gdk3/stable/gdk3-Cursors.html#gdk-cursor-new-from-name Name list
function newCursorFromName(window::Gtk.GtkWindow, name::String)
    ptr = ccall((:gdk_cursor_new_from_name, Gtk.libgdk), Ptr{GObject}, (Ptr{GObject}, Ptr{UInt8}), Gtk.GAccessor.display(window), name)

    if ptr != C_NULL && !haskey(cursorCache, (window, ptr))
        cursorCache[(window, ptr)] = Gtk.GLib.GObjectLeaf(ptr)
    end

    return get(cursorCache, (window, ptr), nothing)
end

function setWindowCursor!(window::Gtk.GtkWindow, cursor::Gtk.GObject)
    return ccall((:gdk_window_set_cursor, Gtk.libgdk), Ptr{GObject}, (Ptr{GObject}, Ptr{GObject}), get_gtk_property(window, :window, Gtk.GObject), cursor)
end

setWindowCursor!(window::Gtk.GtkWindow, name::String) = setWindowCursor!(window, newCursorFromName(window, name))

function getWindowCursor(window::Gtk.GtkWindow)
    ptr = ccall((:gdk_window_get_cursor, Gtk.libgdk), Ptr{GObject}, (Ptr{GObject},), get_gtk_property(window, :window, Gtk.GObject))

    if ptr != C_NULL && !haskey(cursorCache, (window, ptr))
        cursorCache[(window, ptr)] = Gtk.GLib.GObjectLeaf(ptr)
    end

    return get(cursorCache, (window, ptr), newCursorFromName(window, "default"))
end

function changeCursor(func::Function, window::Gtk.GtkWindow, startName::String, stopName::String="")
    startCursor = newCursorFromName(window, startName)
    stopCursor = isempty(stopName) ? getWindowCursor(window) : newCursorFromName(window, stopName)

    setWindowCursor!(window, startCursor)
    func()
    setWindowCursor!(window, stopCursor)
end

# General

function setDefaultDirection(direction::Integer)
    return ccall((:gtk_widget_set_default_direction, Gtk.libgtk), Ptr{}, (Cint,), direction)
end

function initComboBox!(widget::Gtk.GtkComboBoxText, choices::Array{String, 1})
    append!(widget, choices)
    set_gtk_property!(widget, :active, 0)
end

function dropdownString(value::Any)
    return value === nothing ? "nothing" : string(value)
end

function setComboIndex!(widget::Gtk.GtkComboBoxText, choices::Array{T, 1}, item::H; allowCustom::Bool=true) where {T, H}
    if !allowCustom && !(item in choices)
        throw(ArgumentError("The selected value does not exist for the given choices"))
    end

    item = dropdownString(item)
    choices = dropdownString.(choices)

    if !(item in choices)
        push!(choices, item)
        push!(widget, item)
    end

    index = findfirst(isequal(item), choices)
    Gtk.GLib.@sigatom set_gtk_property!(widget, :active, something(index, 1) - 1)

    return index
end

function setEntryText!(entry::Gtk.GtkEntryLeaf, value::Any; updatePlaceholder::Bool=true)
    text = string(value)

    Gtk.GLib.@sigatom GAccessor.text(entry, text)

    if updatePlaceholder
        Gtk.GLib.@sigatom GAccessor.placeholder_text(entry, text)
    end
end

function convertString(str::String, as::Type=String)
    if as == String
        return str

    elseif as == Nothing
        return nothing

    elseif as == Char
        if length(str) == 1
            return str[1]

        else
            error("Expected string with length 1, got $(length(str))")
        end

    elseif as == Bool
        return parse(as, str)

    elseif as <: Number
        return Ahorn.parseNumber(str)

    else
        error("Unsupported return type")
    end
end

function getEntryText(entry::Gtk.GtkEntryLeaf, as::Type=String)
    str = Gtk.GLib.@sigatom Gtk.bytestring(GAccessor.text(entry))
    
    return convertString(str, as)
end

function setTextViewText!(textView::Gtk.GtkTextViewLeaf, value::String="")
    GAccessor.buffer(textView, TextBuffer(text=value))
end

function getTextViewText(textView::Gtk.GtkTextViewLeaf)
    return join(collect(GAccessor.buffer(textView)))
end

function addProviderForScreen(screen::Any, provider::Gtk.GtkCssProviderLeaf)
    return ccall((:gtk_style_context_add_provider_for_screen, Gtk.libgtk), Nothing, (Ptr{Nothing}, Ptr{GObject}, Cuint), screen, provider, 1)
end

function setDialogFolder(dialog::GObject, path::String)
    return ccall((:gtk_file_chooser_set_current_folder, Gtk.libgtk), Cint, (Ptr{GObject}, Ptr{UInt8}), dialog, path)
end

function setDialogFilename(dialog::GObject, path::String)
    return ccall((:gtk_file_chooser_set_current_name, Gtk.libgtk), Cint, (Ptr{GObject}, Ptr{UInt8}), dialog, path)
end

function getProgressDialog(; title::String="", description::String="", filename::String="", stylesheet::String="", parent::Any=GtkNullContainer(), buttons::Tuple{}=())
    pixbuf = isempty(filename) ? Pixbuf(width=1, height=1, has_alpha=true) : Pixbuf(filename=filename, preserve_aspect_ratio=true)
    image = Image(pixbuf, name="dialog_image")
    
    dlg = GtkMessageDialog(title, (),
        Gtk.GtkDialogFlags.DESTROY_WITH_PARENT, Gtk.GtkMessageType.INFO, parent,
        secondary_text=description, image=image
    )
    
    if !isempty(stylesheet)
        screen = Gtk.GAccessor.screen(dlg)
        provider = CssProviderLeaf(filename=stylesheet)

        addProviderForScreen(screen, provider)
    end

    return dlg
end

function setProgressDialogPixbuf!(dlg::Gtk.GObject, pixbuf::Union{Gtk.GdkPixbuf, Ptr{GObject}})
    image = get_gtk_property(dlg, :image, GtkImage)

    set_gtk_property!(image, :visible, true)
    set_gtk_property!(image, :pixbuf, pixbuf)
end

useNativeFileDialogs = isdefined(Gtk, :save_dialog_native) && Gtk.libgtk_version >= v"3.20.0"

# Modified version of standard open dialog
function openDialog(title::AbstractString, parent=GtkNullContainer(), filters::Union{AbstractVector, Tuple}=String[]; folder::String="", native::Bool=useNativeFileDialogs, kwargs...)
    local dlg

    if native
        dlg = GtkFileChooserNative(title, parent, GConstants.GtkFileChooserAction.OPEN, "_Open", "_Cancel"; kwargs...)

    else
        dlg = GtkFileChooserDialog(title, parent, GConstants.GtkFileChooserAction.OPEN, (
                ("_Cancel", GConstants.GtkResponseType.CANCEL),
                ("_Open",   GConstants.GtkResponseType.ACCEPT)
            ); kwargs...)
    end

    dlgp = GtkFileChooser(dlg)

    if !isempty(filters)
        Gtk.makefilters!(dlgp, filters)
    end

    if !isempty(folder)
        setDialogFolder(dlgp, folder)
    end

    response = run(dlg)
    multiple = get_gtk_property(dlg, :select_multiple, Bool)
    local selection

    if response == GConstants.GtkResponseType.ACCEPT
        if multiple
            filename_list = ccall((:gtk_file_chooser_get_filenames, libgtk), Ptr{Gtk._GSList{String}}, (Ptr{GObject},), dlgp)
            selection = String[f for f in Gtk.GList(filename_list, true)]

        else
            selection = Gtk.bytestring(GAccessor.filename(dlgp))
        end

    else
        if multiple
            selection = String[]

        else
            selection = ""
        end
    end

    native ? Gtk.GLib.gc_unref(dlg) : Gtk.destroy(dlg)

    return selection
end

# Modified version of standard save dialog
function saveDialog(title::AbstractString, parent=GtkNullContainer(), filters::Union{AbstractVector, Tuple}=String[]; folder::String="", filename::String="", warnOverwrite::Bool=true, native::Bool=useNativeFileDialogs, kwargs...)
    local dlg

    if native
        dlg = GtkFileChooserNative(title, parent, GConstants.GtkFileChooserAction.SAVE, "_Save", "_Cancel"; kwargs...)

    else
        dlg = GtkFileChooserDialog(title, parent, GConstants.GtkFileChooserAction.SAVE, (
                ("_Cancel", GConstants.GtkResponseType.CANCEL),
                ("_Save",   GConstants.GtkResponseType.ACCEPT)
            ); kwargs...)
    end

    dlgp = GtkFileChooser(dlg)

    if !isempty(folder)
        setDialogFolder(dlgp, folder)
    end

    if !isempty(filename)
        setDialogFilename(dlgp, filename)
    end

    if !isempty(filters)
        Gtk.makefilters!(dlgp, filters)
    end

    ccall((:gtk_file_chooser_set_do_overwrite_confirmation, Gtk.libgtk), Nothing, (Ptr{GObject}, Cint), dlg, warnOverwrite)
    response = run(dlg)

    if response == GConstants.GtkResponseType.ACCEPT
        selection = Gtk.bytestring(GAccessor.filename(dlgp))

    else
        selection = ""
    end

    native ? Gtk.GLib.gc_unref(dlg) : Gtk.destroy(dlg)

    return selection
end

function scalePixbufSimple(pixbuf::Gtk.GdkPixbuf, width::Integer=width(pixbuf), height::Integer=height(pixbuf), method::Int32=GdkInterpType.NEAREST)
    return ccall((:gdk_pixbuf_scale_simple, Gtk.libgdkpixbuf), Ptr{GObject}, (Ptr{GObject}, Cint, Cint, Cint), pixbuf, width, height, method)
end

function pixbufFromSurface(surface::Cairo.CairoSurface, alpha::Bool=true)
    return Pixbuf(data=[Ahorn.ARGB(Ahorn.argb32ToRGBATuple(c)...) for c in getSurfaceData(surface)], has_alpha=alpha)
end

getSurfaceData(surface::Cairo.CairoSurfaceImage) = surface.data

function getSurfaceData(surface::Cairo.CairoSurface)
    imageSurface = CairoImageSurface(zeros(UInt32, floor(Int, height(surface)), floor(Int, width(surface))), Cairo.FORMAT_ARGB32)
    imageSurfaceCtx = CairoContext(imageSurface)

    drawImage(imageSurfaceCtx, surface, 0, 0)

    return imageSurface.data
end

cairoGCCache = Dict{Int, Cairo.CairoContext}()

function getSurfaceContext(surface::Cairo.CairoSurface)
    get!(cairoGCCache, Int(surface.ptr)) do
        creategc(surface)
    end
end

# Borrowed from Gtk.jl repo, build is not installable yet
function g_timeout_add(interval::Integer, cb::Function, user_data::CT) where CT
    callback = @cfunction($cb, Cint, (Ref{CT},) )

    ref, deref = Gtk.GLib.gc_ref_closure(user_data)

    return ccall((:g_timeout_add_full, Gtk.libglib), Cint, (Cint, UInt32, Ptr{Nothing}, Ptr{Nothing}, Ptr{Nothing}), 0, UInt32(interval), callback, ref, deref)
end

# Borrowed from Gtk.jl repo, build is not installable yet
function g_idle_add(cb::Function, user_data::CT) where CT
    callback = @cfunction($cb, Cint, (Ref{CT},) )
    ref, deref = Gtk.GLib.gc_ref_closure(user_data)

    return ccall((:g_idle_add_full, Gtk.libglib), Cint, (Cint, Ptr{Nothing}, Ptr{Nothing}, Ptr{Nothing}), 0, callback, ref, deref)
end

function addIdleCallback(cb::Function, data::CT, timeout::Number=-1) where CT
    if timeout == -1
        g_idle_add(data -> Cint(cb(data)), data)

    else
        g_timeout_add(round(Int, timeout * 1000), data -> Cint(cb(data)), data)
    end
end

waitForIdle() = addIdleCallback(data -> false, nothing)

MenuItemsTypes = Union{Gtk.GtkMenuItem, Gtk.GtkImageMenuItem}