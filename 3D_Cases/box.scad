$fn = 40;

pcb_radius = 5;
pcb_hole_dia = 3;
pcb_hole_x = 150;
pcb_hole_y = 96;
pcb_standoff_height = 8;
pcb_x = pcb_hole_x + 2 * pcb_radius;
pcb_y = pcb_hole_y + 2 * pcb_radius;
pcb_thick = 1.6;
rj45_height = 12.8;

pcb_box_space = 1.5;
box_inner_x = pcb_x + 2 * pcb_box_space;
box_inner_y = pcb_y + 2 * pcb_box_space;
box_inner_radius = pcb_radius + pcb_box_space;

box_thick = 3;
box_outer_x = box_inner_x + 2 * box_thick;
box_outer_y = box_inner_y + 2 * box_thick;
box_outer_z = box_thick + pcb_standoff_height + pcb_thick + rj45_height;
box_outer_radius = box_inner_radius + box_thick;

cover_base_space = 0.16;
cover_thick = 4;
cover_inner_radius = box_outer_radius + cover_base_space;
cover_inner_x = box_outer_x + 2 * cover_base_space;
cover_inner_y = box_outer_y + 2 * cover_base_space;
cover_outer_radius = cover_inner_radius + cover_thick;
cover_outer_x = cover_inner_x + 2 * cover_thick;
cover_outer_y = cover_inner_y + 2 * cover_thick;
cover_outer_z = box_outer_z + 19 + box_thick;

// cube rounded on all vertical edges

module roundbox(x,y,z,r) {
    hull() {
        translate([ x/2-r,  y/2-r, 0]) cylinder(h=z, r=r);
        translate([-x/2+r,  y/2-r, 0]) cylinder(h=z, r=r);
        translate([ x/2-r, -y/2+r, 0]) cylinder(h=z, r=r);
        translate([-x/2+r, -y/2+r, 0]) cylinder(h=z, r=r);
    }
}

// A cylinder with a hole through it, for mounting the PCB.
module post(id, od, x, y, z1, z2) {
    difference() {
        translate([x,y,0]) cylinder(h=z2-z1, r=od/2);
        translate([x,y,z1]) cylinder(h=z2, r=id/2);
    }
}

module cover_power_hole() {
    pcb_top = box_thick + pcb_standoff_height + pcb_thick;
    y = (pcb_top + box_outer_z) / 2;
    translate([-59, -cover_outer_y/2-.1, y])
    rotate([-90,0,0]) 
    translate([0,25,0]) slot(12, 60, 2.0, cover_thick+0.2);
}

module power_hole() {
    pcb_top = box_thick + pcb_standoff_height + pcb_thick;
    y = (pcb_top + box_outer_z) / 2;
    translate([-59, -box_outer_y/2-.1, y])
    rotate([-90,0,0]) 
    slot(6, 4, 2.0, box_thick+0.2);
}

module slot(w,h,r,z) {
    hull() {
        translate([-w/2+r, -h/2+r, 0]) cylinder(h=z, r=r);
        translate([ w/2-r,  h/2-r, 0]) cylinder(h=z, r=r);
        translate([-w/2+r,  h/2-r, 0]) cylinder(h=z, r=r);
        translate([ w/2-r, -h/2+r, 0]) cylinder(h=z, r=r);
    }
}
module usb_connector_left() {
    translate([-pcb_x / 2 - 0.5, -1.2 - 3.8, pcb_thick]) cube([5, 7.6, 2.6]);
}

module usb_connector_right() {
    translate([pcb_x / 2 - 5 + 0.5, +7.3 - 3.8, pcb_thick]) cube([5, 7.6, 2.6]);
}

module usb_hole_left() {
    translate([-box_inner_x/2+.1, -1.2, 3+pcb_standoff_height+box_thick])
    rotate([90,0,-90])
    slot(16, 12, 3, box_thick+0.2);
}

module usb_hole_right() {
    translate([box_inner_x/2-.1, 7.3, 3+pcb_standoff_height+box_thick])
    rotate([90,0,+90])
    slot(16, 12, 3, box_thick+0.2);
}


module rj45() {
    translate([0,0,pcb_standoff_height + box_thick]) union() {
        translate([ pcb_x / 2, 10.5 + 15.3 / 2 - pcb_y / 2, 0]) rotate([0, 0, -90]) rj45_new();
        translate([-pcb_x / 2, 9.95 + 15.3 / 2 - pcb_y / 2, 0]) rotate([0, 0,  90]) rj45_new();
    }
}

module rect(x1, y1, x2, y2) {
    translate([x1, y1, 0]) square([x2-x1, y2-y1]);
}

module rj45_new() {
   w1 = 17.7; w2 = 15.3;
   x1 = -w1/2; x2 = -w2/2; x3 =  w2/2; x4 =  w1/2;
   y1 = -14.2; y2 = 2.8; y3 = 4.5; y4 = 7.0;

   translate([0,0,pcb_thick]) linear_extrude(height=13) union() {
        rect(x2, y1, x3, y4);
        rect(x1, y2, x4, y3);
    }
}

module cover_rj45_holes() {
    translate([0.1-cover_inner_x/2, -pcb_y/2+25/2+5, 0])
        rotate([-90, 0, 90])
        slot(25, 2*box_outer_z, 3, cover_thick+0.7);
    translate([-0.1+cover_inner_x/2, -pcb_y/2+25/2+6, 0])
        rotate([ 90, 0, 90])
        slot(25, 2*box_outer_z, 3, cover_thick+0.7);
}

module wire_holes() {
    translate([0,cover_inner_y/2-.1,cover_outer_z-60/2-10]) rotate([-90,0,0]) translate([0,0,-5]) slot(150,60,10,10);
}


module cover(power, comm) {
    trim_cover = 5;
    difference() {
        translate([0,0,trim_cover]) roundbox(cover_outer_x, cover_outer_y, cover_outer_z-trim_cover, cover_outer_radius);
        translate([0,0,-cover_outer_z + box_outer_z]) roundbox(cover_inner_x, cover_inner_y, cover_outer_z, cover_inner_radius);
        translate([0,0,-box_thick]) roundbox(box_inner_x, box_inner_y, cover_outer_z, box_inner_radius);
        if (power) {cover_power_hole();}
        if (comm) {cover_rj45_holes();}
        wire_holes();
    }
}

module bottom(power, comm, usbleft) {
    difference() {
        roundbox(box_outer_x, box_outer_y, box_outer_z, box_outer_radius);
        translate([0,0,box_thick]) roundbox(box_inner_x, box_inner_y, box_outer_z, box_inner_radius);
        if (usbleft) {usb_hole_left();} else {usb_hole_right();}
        if (power) {power_hole();}
        if (comm) {rj45();}
    }
    post(4.7, 8, -75, -48, 0.1, box_thick + pcb_standoff_height);
    post(4.7, 8,  75, -48, 0.1, box_thick + pcb_standoff_height);
    post(4.7, 8, -75,  48, 0.1, box_thick + pcb_standoff_height);
    post(4.7, 8,  75,  48, 0.1, box_thick + pcb_standoff_height);
}

module pcb(comm, usbleft) {
    translate([0,0,pcb_standoff_height + box_thick])
    union() {
        linear_extrude(height=pcb_thick) difference() {
            hull() {
                translate([-pcb_hole_x / 2, -pcb_hole_y / 2, 0]) circle(d=10);
                translate([-pcb_hole_x / 2,  pcb_hole_y / 2, 0]) circle(d=10);
                translate([ pcb_hole_x / 2, -pcb_hole_y / 2, 0]) circle(d=10);
                translate([ pcb_hole_x / 2,  pcb_hole_y / 2, 0]) circle(d=10);
            }
            translate([-pcb_hole_x / 2, -pcb_hole_y / 2, 0]) circle(d=pcb_hole_dia);
            translate([-pcb_hole_x / 2,  pcb_hole_y / 2, 0]) circle(d=pcb_hole_dia);
            translate([ pcb_hole_x / 2, -pcb_hole_y / 2, 0]) circle(d=pcb_hole_dia);
            translate([ pcb_hole_x / 2,  pcb_hole_y / 2, 0]) circle(d=pcb_hole_dia);
        }
        if (usbleft) {usb_connector_left();} else {usb_connector_right();}
    }
    if (comm) {rj45();}
}

// master
power = true; comm = true; usbleft = true;
// slave
// power = false; comm = true; usbleft = true;
// slat8
// power = true; comm = false; usbleft = true;
// mini
// power = false; comm = false; usbleft = false;


bottom(power, comm, usbleft);
color([0.5,0.5,0.5,0.8]) translate([0,0,0]) cover(power, comm);
// translate([0,0,cover_outer_z]) rotate([180,0,0]) cover(power, comm);

// #pcb(comm, usbleft);
