"""Aureole's deterministic, offline environment workshop. Blender 4.3+.

Run: blender -b --python tools/generate_world.py -- --output assets/generated
All geometry is authored in metres. Rebuilds require no downloaded art assets.
"""
import bpy
import math
import random
import json
import sys
import os
import argparse
from mathutils import Vector
from mathutils.noise import noise_vector

SEED = 41027
rng = random.Random(SEED)
TAU = math.tau
V = Vector


def mix(a, b, t):
    return a * (1 - t) + b * t


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x-a)/(b-a)))
    return t*t*(3-2*t)


def col(a, b, t):
    return tuple(mix(x,y,t) for x,y in zip(a,b))


def noise(p, scale=1):
    return noise_vector(V(p)*scale, noise_basis='PERLIN_ORIGINAL').x


def frame(n):
    n = V(n).normalized()
    u = n.cross(V((0,1,0)))
    if u.length < .01:
        u = n.cross(V((1,0,0)))
    u.normalize()
    return u, n.cross(u).normalized(), n


class Geometry:
    """Material-batched geometry with vertex pigment and shared normals."""
    def __init__(self):
        self.batches = {}

    def add(self, key, vertices, faces, colors, flat=False):
        batch = self.batches.setdefault((key,flat), [[],[],[]])
        start = len(batch[0])
        batch[0].extend(vertices)
        batch[1].extend([tuple(start+i for i in f) for f in faces])
        if isinstance(colors[0], (int,float)):
            colors = [colors]*len(vertices)
        batch[2].extend(colors)

    def ellipsoid(self, p, scale, color, key='stone', seg=12, rings=7, deform=0, basis=None):
        vertices, faces = [], []
        p=V(p)
        for j in range(rings+1):
            phi=math.pi*j/rings
            for i in range(seg):
                theta=TAU*i/seg
                n=V((math.sin(phi)*math.cos(theta),math.cos(phi),math.sin(phi)*math.sin(theta)))
                f=1+deform*noise(n*3+p)
                point=V((n.x*scale[0],n.y*scale[1],n.z*scale[2]))*f
                if basis:
                    point=basis[0]*point.x+basis[1]*point.y+basis[2]*point.z
                vertices.append(p+point)
        for j in range(rings):
            for i in range(seg):
                a=j*seg+i; b=j*seg+(i+1)%seg
                faces.append((a,b,b+seg,a+seg))
        colors=[tuple(c*(.94+.09*noise(v*4)) for c in color) for v in vertices]
        self.add(key,vertices,faces,colors)

    def tube(self, points, radii, color, key='stone', sides=8, closed=False, flatten=1):
        points=[V(p) for p in points]
        vertices,faces=[],[]
        for i,p in enumerate(points):
            tangent=points[(i+1)%len(points)]-points[i-1] if closed else points[min(i+1,len(points)-1)]-points[max(0,i-1)]
            u,v,_=frame(tangent)
            radius=radii[i] if isinstance(radii,list) else radii
            for j in range(sides):
                a=TAU*j/sides
                vertices.append(p+radius*(u*math.cos(a)+v*math.sin(a)*flatten))
        for i in range(len(points) if closed else len(points)-1):
            for j in range(sides):
                a=i*sides+j; b=i*sides+(j+1)%sides
                faces.append((a,b,((i+1)%len(points))*sides+(j+1)%sides,((i+1)%len(points))*sides+j))
        if not closed:
            faces.append(tuple(range(sides-1,-1,-1)))
            faces.append(tuple((len(points)-1)*sides+j for j in range(sides)))
        self.add(key,vertices,faces,color)

    def crystal(self,p,n,length,radius,color):
        u,v,n=frame(n); p=V(p)
        vertices=[]
        sides=5
        for h,r in [(0,radius*.83),(.72*length,radius),(length,radius*.04)]:
            for j in range(sides):
                a=TAU*j/sides
                vertices.append(p+n*h+(u*math.cos(a)+v*math.sin(a))*r)
        faces=[]
        for k in range(2):
            for j in range(sides):
                a=k*sides+j; b=k*sides+(j+1)%sides
                faces.append((a,b,b+sides,a+sides))
        self.add('crystal',vertices,faces,color,True)

    def torus(self,p,n,radius,tube,color,key='metal',segments=80,sides=8,arc=TAU):
        u,v,n=frame(n)
        points=[V(p)+(u*math.cos(arc*i/segments)+v*math.sin(arc*i/segments))*radius for i in range(segments+(arc<TAU))]
        self.tube(points,tube,color,key,sides,closed=arc==TAU)

    def save(self, name):
        objects=[]
        for (key,flat),(vertices,faces,colors) in self.batches.items():
            mesh=bpy.data.meshes.new(name+'_'+key)
            mesh.from_pydata(vertices,[],faces)
            mesh.materials.append(materials[key])
            pigment=mesh.color_attributes.new(name='Pigment',type='FLOAT_COLOR',domain='POINT')
            for c,value in zip(pigment.data,colors):
                c.color=(*value[:3],1)
            for poly in mesh.polygons:
                poly.use_smooth=not flat
            ob=bpy.data.objects.new(name+'_'+key,mesh)
            bpy.context.collection.objects.link(ob)
            objects.append(ob)
        return objects


bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
materials={}
for name,rough,metal,emission in [
    ('sand',.82,0,0),('stone',.9,0,0),('ivory',.38,0,0),
    ('crystal',.24,.18,0),('metal',.3,.78,0),('dark_metal',.42,.7,0),
    ('leaf',.65,0,0),('bark',.86,0,0),('water',.24,.25,0),
    ('foam',.5,0,.12),('light',.3,.3,2.0),('coral',.7,0,0)]:
    mat=bpy.data.materials.new(name)
    mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF')
    vc=mat.node_tree.nodes.new('ShaderNodeVertexColor'); vc.layer_name='Pigment'
    mat.node_tree.links.new(vc.outputs['Color'],bs.inputs['Base Color'])
    bs.inputs['Roughness'].default_value=rough
    bs.inputs['Metallic'].default_value=metal
    if emission:
        mat.node_tree.links.new(vc.outputs['Color'],bs.inputs['Emission Color'])
        bs.inputs['Emission Strength'].default_value=emission
    materials[name]=mat

BASIN=V((-.43,-.14,.892)).normalized()
BU,BV,_=frame(BASIN)


def basin_coords(n):
    a=math.acos(max(-1,min(1,n.dot(BASIN))))
    t=math.atan2(n.dot(BV),n.dot(BU))
    edge=.675+.038*math.sin(3*t+.3)+.025*math.sin(7*t+1)
    return a/edge,t,edge


def radius(n):
    f,_,_=basin_coords(n)
    base=4.0+.14*noise(n,2.1)+.065*noise(n,7)
    dune=.045*math.sin(n.x*26+n.y*17+noise(n,3)*3)
    base+=dune*smooth(-.4,.65,n.x)
    return base-.37*(1-smooth(.89,1.15,f))


def on_surface(n,offset=0):
    n=V(n).normalized()
    return n*(radius(n)+offset)


G=Geometry()
# A displaced closed globe, with geographically coherent pigments.
vertices,faces,colors=[],[],[]
N,M=256,128
for j in range(M+1):
    phi=math.pi*j/M
    for i in range(N):
        theta=TAU*i/N
        n=V((math.sin(phi)*math.cos(theta),math.cos(phi),math.sin(phi)*math.sin(theta)))
        p=n*radius(n)
        f,_,_=basin_coords(n)
        pigment=col((.49,.235,.105),(.8,.57,.30),smooth(-.85,.55,n.y))
        pigment=col(pigment,(.92,.73,.44),1-smooth(1,1.26,f))
        forest=smooth(.2,.65,n.y)*smooth(.05,.65,n.x)*smooth(-.4,.3,n.z)
        pigment=col(pigment,(.22,.39,.24),forest*.77)
        pigment=tuple(c*(.96+.08*noise(p,5)) for c in pigment)
        vertices.append(p); colors.append(pigment)
for j in range(M):
    for i in range(N):
        a=j*N+i; b=j*N+(i+1)%N
        faces.append((a,b,b+N,a+N))
G.add('sand',vertices,faces,colors)

# Weathered horizontal mineral shelves on the lower hemisphere.
for band in range(8):
    y=-1.95-band*.21
    points=[]
    for i in range(240):
        t=TAU*i/240
        yy=y+.07*math.sin(t*4+band)+.025*math.sin(t*13)
        n=V((math.sqrt(max(0,1-(yy/4)**2))*math.cos(t),yy/4,math.sqrt(max(0,1-(yy/4)**2))*math.sin(t)))
        points.append(on_surface(n,.012))
    G.tube(points,.024+band*.001,col((.55,.29,.14),(.29,.18,.18),band/10),'stone',5,True)

# Sculpted dune crests use the same terrain function, so they sit on the ground.
for k in range(22):
    points=[]
    for i in range(46):
        x=.12+k*.044+i*.002
        y=-.48+i*.021+.036*math.sin(i*.11+k*.6)
        if x*x+y*y>.94: continue
        n=V((x,y,math.sqrt(1-x*x-y*y)))
        if basin_coords(n)[0]<1.13: continue
        points.append(on_surface(n,.016))
    if len(points)>3:
        G.tube(points,[.003+.012*math.sin(math.pi*i/(len(points)-1)) for i in range(len(points))],(.85,.62,.34),'sand',5)

# Organic spherical sea, with a shelf tint and an irregular shoreline.
sea=Geometry(); vertices=[]; colors=[]; faces=[]
S,R=180,48
for j in range(R+1):
    for i in range(S):
        t=TAU*i/S
        edge=.675+.038*math.sin(3*t+.3)+.025*math.sin(7*t+1)
        a=edge*.97*j/R
        n=BASIN*math.cos(a)+(BU*math.cos(t)+BV*math.sin(t))*math.sin(a)
        vertices.append(n*3.905)
        c=col((.018,.23,.28),(.17,.72,.66),smooth(.15,1,j/R))
        colors.append(c)
for j in range(R):
    for i in range(S):
        a=j*S+i; b=j*S+(i+1)%S
        faces.append((a,a+S,b+S,b))
sea.add('water',vertices,faces,colors)
sea.save('TidalSea')
for fct in [.973,.942]:
    points=[]
    for i in range(240):
        t=TAU*i/240
        edge=.675+.038*math.sin(3*t+.3)+.025*math.sin(7*t+1)
        a=edge*fct
        n=BASIN*math.cos(a)+(BU*math.cos(t)+BV*math.sin(t))*math.sin(a)
        points.append(n*3.922)
    G.tube(points,.009 if fct<.96 else .017,(.64,.90,.81),'foam',5,True)
# Fine wavelets in the lagoon: carefully broken arcs, not a wireframe.
for k in range(28):
    a=rng.uniform(.14,.58); start=rng.uniform(0,TAU); length=rng.uniform(.15,.5)
    points=[]
    for i in range(20):
        t=start+length*i/19
        n=BASIN*math.cos(a)+(BU*math.cos(t)+BV*math.sin(t))*math.sin(a)
        points.append(n*3.93)
    G.tube(points,[.003+.004*math.sin(math.pi*i/19) for i in range(20)],(.29,.75,.71),'foam',4)

# Great curled aragonite crest: a ribbed swept sculpture, ivory outside / glacial inside.
control=[(-3.1,.9,-.6),(-3.85,2.1,-.5),(-3.9,3.6,-.35),(-2.9,4.85,-.1),(-1.45,5.05,.1),(-.4,4.45,.3),(-.62,3.67,.45),(-1.3,3.55,.55)]


def catmull(points,steps=15):
    points=[V(points[0])]+[V(p) for p in points]+[V(points[-1])]
    result=[]
    for i in range(1,len(points)-2):
        a,b,c,d=points[i-1:i+3]
        for j in range(steps):
            t=j/steps
            result.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
    result.append(V(points[-2])); return result


crest=catmull(control)
vertices=[]; colors=[]; faces=[]
K=40
for i,p in enumerate(crest):
    t=i/(len(crest)-1)
    tangent=crest[min(i+1,len(crest)-1)]-crest[max(i-1,0)]
    tangent.normalize(); u=V((-tangent.y,tangent.x,0)).normalized(); v=tangent.cross(u).normalized()
    width=mix(.93,.09,t**.82)
    for j in range(K):
        a=TAU*j/K
        rib=1+.075*math.cos(a*10+t*7)
        pos=p+(u*math.cos(a)*width+v*math.sin(a)*width*.62)*rib
        vertices.append(pos)
        c=col((.72,.67,.54),(.93,.96,.89),smooth(.03,.65,t))
        c=col(c,(.50,.79,.79),max(0,math.sin(a))*.26)
        colors.append(c)
for i in range(len(crest)-1):
    for j in range(K):
        a=i*K+j; b=i*K+(j+1)%K
        faces.append((a,b,b+K,a+K))
G.add('ivory',vertices,faces,colors)
for ridge in range(12):
    points=[]; widths=[]
    a=TAU*ridge/12
    for i,p in enumerate(crest):
        t=i/(len(crest)-1)
        tangent=(crest[min(i+1,len(crest)-1)]-crest[max(i-1,0)]).normalized()
        u=V((-tangent.y,tangent.x,0)).normalized(); v=tangent.cross(u).normalized()
        width=mix(.93,.09,t**.82)
        points.append(p+(u*math.cos(a)*width+v*math.sin(a)*width*.62)*1.055)
        widths.append(.017+.028*(1-t))
    G.tube(points,widths,(.96,.93,.82),'ivory',6)
for i in range(64):
    t=rng.uniform(0,.64); p=crest[int(t*(len(crest)-1))]
    n=V((rng.uniform(-.8,.3),rng.uniform(.4,1),rng.uniform(-.1,.7))).normalized()
    G.crystal(p+V((rng.uniform(-.5,.2),.13,rng.uniform(-.35,.35))),n,rng.uniform(.22,.86)*(1-t),rng.uniform(.06,.14),col((.48,.74,.73),(.91,.93,.84),rng.random()))
# Mineral fans at the foot connect the crest to the terrain.
for i in range(52):
    n=V((-rng.uniform(.6,.87),rng.uniform(.1,.55),rng.uniform(.25,.65))).normalized()
    p=on_surface(n,-.08)
    G.crystal(p,(n+V((-.3,.35,0))).normalized(),rng.uniform(.18,.8),rng.uniform(.06,.17),(.66,.83,.78))

# Brass astronomical gate, embedded in the jade highlands.
gate_n=V((.45,.36,.82)).normalized()
gate_p=on_surface(gate_n,.8)
gu,gv,_=frame(gate_n)
for r,w,key,color in [(1.12,.14,'dark_metal',(.12,.20,.23)),(1.26,.065,'metal',(.66,.41,.17)),(.99,.05,'metal',(.82,.60,.29)),(1.35,.028,'metal',(.58,.38,.18)),(1.06,.017,'light',(.15,.73,.70))]:
    G.torus(gate_p,gate_n,r,w,color,key,96,10)
for i in range(48):
    t=TAU*i/48
    d=gu*math.cos(t)+gv*math.sin(t)
    p=gate_p+d*1.16
    G.tube([p-gate_n*.13,p+gate_n*.15],.025,(.88,.65,.28),'metal',6)
    if i%4==0:
        G.tube([gate_p+d*.995+gate_n*.045,gate_p+d*1.30+gate_n*.045],.022,(.59,.42,.22),'metal',6)
        G.ellipsoid(gate_p+d*1.28+gate_n*.08,(.045,.045,.045),(.26,.91,.79),'light',8,4)
for i in range(7):
    t=TAU*i/7
    d=gu*math.cos(t)+gv*math.sin(t)
    start=gate_p+d*1.14-gate_n*.05
    end=on_surface((gate_p+d*1.15).normalized(),.03)
    G.tube([start,end],.075,(.27,.25,.20),'dark_metal',8)
G.ellipsoid(gate_p,(.21,.21,.21),(.11,.52,.53),'crystal',16,10)
for ang in [-.35,.6]:
    n=(gate_n+gu*ang).normalized()
    G.torus(gate_p,n,.53,.019,(.73,.48,.22),'metal',64,6)

# Ocean sanctuary / lighthouse, on a rock island with contour terraces.
island_n=V((-.59,.06,.81)).normalized(); ip=island_n*3.91
iu,iv,_=frame(island_n)
for k in range(4):
    G.ellipsoid(ip+island_n*(k*.08-.02),(.43-k*.045,.11,.32-k*.02),col((.35,.36,.26),(.79,.65,.4),k/4),'stone',24,6,basis=(iu,island_n,iv))
base=ip+island_n*.2
G.tube([base,base+island_n*.69],[.16,.12],(.86,.79,.58),'ivory',12)
for h in [.06,.53,.68]:
    G.torus(base+island_n*h,island_n,.17,.025,(.57,.37,.16),'metal',32,6)
G.tube([base+island_n*.65,base+island_n*.91],[.20,.015],(.12,.35,.35),'metal',12)
G.ellipsoid(base+island_n*.6+V((0,0,.115)),(.055,.085,.055),(.96,.50,.15),'light',10,6)
# A curved stepping-stone crossing, and its delicate brass handrail.
crossing=[]
for i in range(12):
    a=i/11
    n=(island_n*(1-a)+V((-.04,.37,.93))*a).normalized()
    p=n*(3.97+.13*math.sin(a*math.pi)); crossing.append(p+n*.11)
    u,v,_=frame(n)
    G.ellipsoid(p,(.12,.035,.075),(.62,.48,.27),'stone',10,4,basis=(u,n,v))
    if i%2==0:
        G.tube([p+u*.11,p+u*.11+n*.20],.013,(.50,.35,.19),'metal',5)
G.tube(crossing,.012,(.67,.48,.25),'metal',5)

# A tiny desert caravan, with red dotted navigation trails on the actual globe.
for i in range(126):
    t=i/125
    x=.04+.82*t
    y=-.59+.34*math.sin(t*math.pi*1.1)+.18*t
    n=V((x,y,math.sqrt(max(.02,1-x*x-y*y)))).normalized()
    if basin_coords(n)[0]<1.08: continue
    p=on_surface(n,.035)
    G.ellipsoid(p,(.018,.018,.018),(.82,.12,.065),'coral',6,4)
for x,y in [(.34,-.25),(.43,-.21),(.52,-.17)]:
    n=V((x,y,math.sqrt(1-x*x-y*y))); p=on_surface(n,.10); u,v,n=frame(n)
    G.ellipsoid(p,(.12,.08,.07),(.52,.27,.12),'bark',10,5,basis=(u,n,v))
    for side in [-1,1]:
        for sign in [-1,1]:
            q=p+u*.075*side+v*.04*sign
            G.tube([q,q-n*.1],.015,(.31,.20,.12),'bark',5)
    G.ellipsoid(p+n*.09,(.075,.055,.06),(.82,.35,.13),'coral',10,5)
    G.tube([p+u*.09,p+u*.16+n*.15,p+u*.20+n*.14],.025,(.57,.32,.15),'bark',6)

# Ancient equatorial chain: individual interlocking elliptical links.
for i in range(30):
    t=-.1+i*.045
    n=V((math.cos(t),-.3+.07*math.sin(t*3),math.sin(t))).normalized()
    p=on_surface(n,.12)
    normal=V((0,1,0)) if i%2 else n
    u,v,_=frame(normal)
    points=[p+u*math.cos(a)*.102+v*math.sin(a)*.066 for a in [TAU*k/14 for k in range(14)]]
    G.tube(points,.018,(.46,.32,.18),'metal',5,True)

# Strata rocks, cactus and desert plants follow dry, open ground.
instances=[]
for i in range(1600):
    z=rng.uniform(-1,1); t=rng.uniform(0,TAU)
    n=V((math.sqrt(1-z*z)*math.cos(t),z,math.sqrt(1-z*z)*math.sin(t)))
    f,_,_=basin_coords(n)
    if f<1.1: continue
    p=on_surface(n)
    forest=(n.y>.28 and n.x>.05 and n.z>-.5) or (n.z<-.4 and n.y>-.15)
    if forest and rng.random()<.7:
        # Preserve negative space around the armillary and the shore.
        if (p-gate_p).length<1.4: continue
        scale=rng.uniform(.65,1.3)
        instances.append({'kind':'tree'+str(i%3),'p':list(p),'n':list(n),'scale':scale,'yaw':rng.uniform(0,TAU)})
    elif rng.random()<.63:
        scale=rng.uniform(.035,.15)
        instances.append({'kind':'rock','p':list(p),'n':list(n),'scale':scale,'yaw':rng.uniform(0,TAU)})
    elif rng.random()<.37:
        instances.append({'kind':'grass','p':list(p),'n':list(n),'scale':rng.uniform(.6,1.2),'yaw':rng.uniform(0,TAU)})
    elif n.x>.15 and n.y<.25 and i%5==0:
        G.tube([p,p+n*.28],[.045,.034],(.19,.39,.24),'leaf',8)
        u,v,_=frame(n)
        for sign in [-1,1]:
            G.tube([p+n*.1,p+n*.12+u*.09*sign,p+n*.23+u*.1*sign],[.025,.025,.02],(.22,.42,.25),'leaf',6)

# Shore pebbles and small red corals form an ecologically readable littoral belt.
for i in range(165):
    t=rng.uniform(0,TAU); edge=.675+.038*math.sin(3*t+.3)+.025*math.sin(7*t+1)
    a=edge*rng.uniform(1.10,1.20)
    n=BASIN*math.cos(a)+(BU*math.cos(t)+BV*math.sin(t))*math.sin(a)
    p=on_surface(n,.02); u,v,_=frame(n)
    size=rng.uniform(.018,.055)
    G.ellipsoid(p,(size,size*.6,size*.8),(.78,.68,.46),'stone',7,4)
    if i%9==0:
        for k in range(3):
            q=p+u*(k-1)*.04
            G.tube([q,q+n*rng.uniform(.1,.24)+v*.03],[.018,.01],(.72,.23,.16),'coral',5)

# Fungi grow in the shaded woodland edge, with visible caps and gills.
for i in range(48):
    n=V((rng.uniform(.07,.63),rng.uniform(.55,.83),rng.uniform(.35,.7))).normalized()
    p=on_surface(n,.02); u,v,_=frame(n); size=rng.uniform(.06,.12)
    G.tube([p,p+n*size*1.5],size*.16,(.73,.71,.51),'ivory',6)
    G.ellipsoid(p+n*size*1.5,(size,size*.32,size),(.57,.27,.17),'coral',12,5,basis=(u,n,v))

# A sail-backed sky ray, entirely sculpted mesh, gliding above the lagoon.
ray=Geometry(); center=V((-.65,.3,5.02))
vertices=[]; faces=[]; colors=[]
for j in range(9):
    t=j/8
    for i in range(33):
        x=(i/32*2-1)
        wing=1.03*math.sin(math.pi*t)**.65
        vertices.append(center+V((x*wing,.19*math.sin(abs(x)*math.pi)*math.sin(math.pi*t),(.5-t)*.62+.32*abs(x)**1.3)))
        colors.append(col((.14,.34,.37),(.71,.73,.48),abs(x)*.85))
for j in range(8):
    for i in range(32):
        a=j*33+i;faces.append((a,a+1,a+34,a+33))
ray.add('ivory',vertices,faces,colors)
ray.ellipsoid(center,(.12,.09,.30),(.16,.36,.37),'ivory',16,8)
ray.tube([center+V((0,0,-.23)),center+V((.04,.05,-.6)),center+V((.23,.15,-.9))],[.04,.022,.004],(.24,.42,.38),'ivory',8)
for side in [-1,1]:
    ray.ellipsoid(center+V((side*.085,.065,.14)),(.022,.022,.022),(.98,.66,.19),'light',8,4)
ray.save('SkyRay')

# Airborne rock reliquary and its suspended roots.
for center,size in [((4.75,-.9,-.5),.36),((-4.8,-1.75,.2),.25),((3.6,4.4,-2),.18)]:
    p=V(center)
    G.ellipsoid(p,(size,size*.62,size*.7),(.38,.30,.25),'stone',14,7,.22)
    for k in range(4):
        q=p+V((rng.uniform(-size,size),-.1,rng.uniform(-size,size)))
        G.tube([q,q+V((.03,-size*.9,.02)),q+V((.08,-size*1.5,.03))],[.022,.011,.002],(.26,.23,.18),'bark',5)
    G.crystal(p+V((0,.1,0)),(0,1,0),size*.9,size*.24,(.46,.77,.70))

static_objects=G.save('World')

# Reusable tree families: fluted trunks, branch hierarchy, multi-lobed canopies.
for family in range(3):
    tree=Geometry()
    height=[.44,.58,.35][family]
    tree.tube([(0,0,0),(.015,height*.45,0),(-.015,height,0)],[.038,.028,.013],(.26,.20,.12),'bark',7)
    for k in range(5):
        a=TAU*k/5+family
        branch=V((math.cos(a)*.13,height*.72+(k%2)*.06,math.sin(a)*.13))
        tree.tube([V((0,height*.45,0)),branch],[.017,.007],(.31,.24,.13),'bark',6)
        color=[(.16,.37,.24),(.15,.47,.38),(.38,.51,.20)][family]
        color=tuple(c*rng.uniform(.92,1.12) for c in color)
        tree.ellipsoid(branch+V((0,.09,0)),(.17,.20,.16),color,'leaf',12,8,.16)
    tree.ellipsoid((0,height+.08,0),(.17,.24,.16),[(.21,.43,.28),(.24,.58,.46),(.46,.56,.25)][family],'leaf',14,9,.12)
    tree.save('Tree'+str(family))
rock=Geometry(); rock.ellipsoid((0,.3,0),(1,.7,.76),(.48,.38,.27),'stone',9,5,.32); rock.save('Rock')
grass=Geometry()
for i in range(7):
    a=TAU*i/7
    grass.tube([(0,0,0),(.025*math.cos(a),.07,.025*math.sin(a)),(.06*math.cos(a),.14+rng.random()*.05,.06*math.sin(a))],[.009,.007,.001],(.41,.44,.23),'leaf',4)
grass.save('Grass')


def export_group(prefix,path):
    bpy.ops.object.select_all(action='DESELECT')
    obs=[o for o in bpy.context.scene.objects if o.name.startswith(prefix+'_')]
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    bpy.ops.export_scene.gltf(filepath=path,export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_normals=True,export_cameras=False,export_lights=False)
    return obs


args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
parser=argparse.ArgumentParser();parser.add_argument('--output',default='assets/generated');options=parser.parse_args(args)
out=os.path.abspath(options.output);os.makedirs(out,exist_ok=True)
# Blender uses Z-up; our workshop uses Godot's Y-up. Disable the axis conversion
# by rotating at export; the glTF root then preserves our authored coordinates.
for ob in bpy.context.scene.objects:
    for vertex in ob.data.vertices:
        x,y,z=vertex.co
        vertex.co=(x,-z,y)
manifest={'seed':SEED,'instances':instances,'assets':{}}
for prefix in ['World','TidalSea','SkyRay','Tree0','Tree1','Tree2','Rock','Grass']:
    objects=export_group(prefix,os.path.join(out,prefix.lower()+'.glb'))
    manifest['assets'][prefix]={'vertices':sum(len(o.data.vertices) for o in objects),'polygons':sum(len(o.data.polygons) for o in objects),'batches':len(objects)}
with open(os.path.join(out,'world_manifest.json'),'w') as f:json.dump(manifest,f,separators=(',',':'))
print('AUREOLE_WORKSHOP_COMPLETE',json.dumps({k:v for k,v in manifest['assets'].items()}))
