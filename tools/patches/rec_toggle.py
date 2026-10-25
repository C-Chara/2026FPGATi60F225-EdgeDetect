"""K1+K2 long hold toggles shape recognition; TNR and fragment removal fixed on."""
import io
import sys

ROOT = sys.argv[1]


def load(path):
    raw = io.open(ROOT + '/' + path, newline='', encoding='latin-1').read()
    return raw.replace('\r\n', '\n'), '\r\n' in raw


def save(path, s, crlf):
    io.open(ROOT + '/' + path, 'w', newline='', encoding='latin-1').write(s.replace('\n', '\r\n') if crlf else s)


def sub(s, old, new, count=1):
    assert s.count(old) == count, (old[:80], s.count(old))
    return s.replace(old, new)


p = 'src/edge/key_threshold.v'
s, crlf = load(p)
s = sub(s, "//   1 -> 2 -> 3 -> 0 -> 1 (the top level decides what each value means).\n",
        "//   1 <-> 2 (the top level decides what each value means).\n")
s = sub(s, "                    else tnr_mode<=tnr_mode+2'd1;\n",
        "                    else tnr_mode<=(tnr_mode==2'd1) ? 2'd2 : 2'd1;\n")
save(p, s, crlf)

p = 'src/edge/fps_osd.v'
s, crlf = load(p)
s = sub(s, "//   FRG ON / FRG OFF  isolated edge fragment removal\n",
        "//   REC ON / REC OFF  shape recognition (circle / rectangle labels)\n")
s = sub(s, "    input wire fragment_on,\n", "    input wire recognition_on,\n")
s = sub(s, "                             (row == 5'd7) ? (fragment_on ? 4'd6 : 4'd7) :\n",
        "                             (row == 5'd7) ? (recognition_on ? 4'd6 : 4'd7) :\n")
s = sub(s, "                0:symbol=G_F; 1:symbol=G_R; 2:symbol=G_G;\n"
        "                4:symbol=G_O;\n"
        "                5:symbol=fragment_on ? G_N : G_F;\n"
        "                6:symbol=fragment_on ? G_BLANK : G_F;\n",
        "                0:symbol=G_R; 1:symbol=G_E; 2:symbol=G_C;\n"
        "                4:symbol=G_O;\n"
        "                5:symbol=recognition_on ? G_N : G_F;\n"
        "                6:symbol=recognition_on ? G_BLANK : G_F;\n")
save(p, s, crlf)

p = 'example_top.v'
s, crlf = load(p)
s = sub(s, "\t// K1+K2 long hold steps four states (power-up first):\n"
        "\t//   TNR ON + FRG ON -> TNR ON + FRG OFF -> TNR OFF + FRG OFF -> TNR OFF + FRG ON\n"
        "\t// (FRG = isolated edge fragment removal, see edge_fragment_filter).\n"
        "\twire [1:0] tnr_key_mode;\n"
        "\twire tnr_key_on = (tnr_key_mode == 2'd1) || (tnr_key_mode == 2'd2);\n"
        "\twire fragment_key_on = (tnr_key_mode == 2'd1) || (tnr_key_mode == 2'd0);\n"
        "\twire [1:0] tnr_mode = (TNR_ENABLE && tnr_key_on) ? 2'd1 : 2'd0;\n",
        "\t// TNR and fragment removal are always on (measured on the board:\n"
        "\t// edge flicker ~300 -> ~7 pixels per frame). The K1+K2 long hold now\n"
        "\t// switches shape recognition (circle / rectangle labels): off at\n"
        "\t// power-up for the basic demo, on for the advanced part.\n"
        "\twire [1:0] tnr_key_mode;\n"
        "\twire recognition_on = (tnr_key_mode == 2'd2);\n"
        "\twire fragment_key_on = 1'b1;\n"
        "\twire [1:0] tnr_mode = TNR_ENABLE ? 2'd1 : 2'd0;\n")
s = sub(s, "\t\t.fragment_on(FRAGMENT_FILTER_ENABLE && fragment_key_on),\n",
        "\t\t.recognition_on(recognition_on),\n")
s = sub(s, "\t\t.found(rect_found), .center_x(rect_cx), .center_y(rect_cy),\n",
        "\t\t.found(rect_found && recognition_on), .center_x(rect_cx), .center_y(rect_cy),\n")
s = sub(s, "\t\t.found(circle_found), .center_x(circle_x), .center_y(circle_y),\n\t\t.radius_px(circle_radius),\n\t\t.box_x0",
        "\t\t.found(circle_found && recognition_on), .center_x(circle_x), .center_y(circle_y),\n\t\t.radius_px(circle_radius),\n\t\t.box_x0")
save(p, s, crlf)

x = io.open(ROOT + '/Ti60_Demo.xml', newline='').read()
assert x.count('value="0x20261035"') == 1
io.open(ROOT + '/Ti60_Demo.xml', 'w', newline='').write(x.replace('value="0x20261035"', 'value="0x20261036"'))
print('ok')
