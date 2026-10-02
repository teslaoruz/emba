"""A silent MPRIS player that claims to be playing, for testing Emba's dancing.

    python3 dev/fake_mpris.py [SECONDS]
"""
import sys

from gi.repository import Gio, GLib

XML = """<node>
 <interface name="org.mpris.MediaPlayer2">
  <property name="Identity" type="s" access="read"/>
  <property name="CanQuit" type="b" access="read"/><property name="CanRaise" type="b" access="read"/>
  <property name="HasTrackList" type="b" access="read"/>
  <property name="SupportedUriSchemes" type="as" access="read"/><property name="SupportedMimeTypes" type="as" access="read"/>
 </interface>
 <interface name="org.mpris.MediaPlayer2.Player">
  <property name="PlaybackStatus" type="s" access="read"/>
  <property name="Metadata" type="a{sv}" access="read"/>
  <property name="CanPlay" type="b" access="read"/><property name="CanPause" type="b" access="read"/>
  <property name="CanControl" type="b" access="read"/>
  <property name="CanGoNext" type="b" access="read"/><property name="CanGoPrevious" type="b" access="read"/>
  <property name="CanSeek" type="b" access="read"/>
 </interface>
</node>"""
PROPS = {
    "Identity": GLib.Variant("s", "Emba test"), "CanQuit": GLib.Variant("b", False),
    "CanRaise": GLib.Variant("b", False), "HasTrackList": GLib.Variant("b", False),
    "SupportedUriSchemes": GLib.Variant("as", []), "SupportedMimeTypes": GLib.Variant("as", []),
    "PlaybackStatus": GLib.Variant("s", "Playing"),
    "Metadata": GLib.Variant("a{sv}", {"xesam:title": GLib.Variant("s", "Bamboo Groove"),
                                        "mpris:trackid": GLib.Variant("o", "/emba/1")}),
    "CanPlay": GLib.Variant("b", True), "CanPause": GLib.Variant("b", True), "CanControl": GLib.Variant("b", True),
    "CanGoNext": GLib.Variant("b", False), "CanGoPrevious": GLib.Variant("b", False), "CanSeek": GLib.Variant("b", False),
}
node = Gio.DBusNodeInfo.new_for_xml(XML)
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
for iface in node.interfaces:
    bus.register_object("/org/mpris/MediaPlayer2", iface, None, lambda *a: PROPS.get(a[4]), None)
Gio.bus_own_name_on_connection(bus, "org.mpris.MediaPlayer2.embatest", 0, None, None)
loop = GLib.MainLoop()
GLib.timeout_add_seconds(int(sys.argv[1]) if len(sys.argv) > 1 else 20, loop.quit)
loop.run()
