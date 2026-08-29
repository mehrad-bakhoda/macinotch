'use client';

import { Canvas, useFrame } from '@react-three/fiber';
import { useMemo, useRef } from 'react';
import * as THREE from 'three';

const COLS = 44;
const ROWS = 14;
const COUNT = COLS * ROWS;

function BarField() {
  const mesh = useRef<THREE.InstancedMesh>(null);
  const dummy = useMemo(() => new THREE.Object3D(), []);
  const colour = useMemo(() => new THREE.Color(), []);

  useFrame(({ clock }) => {
    if (!mesh.current) return;
    const t = clock.getElapsedTime();

    for (let i = 0; i < COUNT; i++) {
      const col = i % COLS;
      const row = Math.floor(i / COLS);
      const x = (col - COLS / 2) * 0.52;
      const z = (row - ROWS / 2) * 0.52;

      const distance = Math.sqrt(x * x + z * z);
      const wave =
        Math.sin(distance * 0.85 - t * 1.1) * 0.5 +
        Math.sin(col * 0.24 + t * 0.62) * 0.32 +
        Math.sin(row * 0.31 - t * 0.44) * 0.22;

      const height = Math.max(0.06, 0.5 + wave * 0.72);

      dummy.position.set(x, height / 2 - 0.6, z);
      dummy.scale.set(0.09, height, 0.09);
      dummy.updateMatrix();
      mesh.current.setMatrixAt(i, dummy.matrix);

      const heat = THREE.MathUtils.clamp((height - 0.2) / 1.5, 0, 1);
      colour.setRGB(
        0.09 + heat * 0.92,
        0.07 + heat * 0.42,
        0.06 + heat * 0.11,
      );
      mesh.current.setColorAt(i, colour);
    }

    mesh.current.instanceMatrix.needsUpdate = true;
    if (mesh.current.instanceColor) mesh.current.instanceColor.needsUpdate = true;
  });

  return (
    <instancedMesh ref={mesh} args={[undefined, undefined, COUNT]}>
      <boxGeometry args={[1, 1, 1]} />
      <meshBasicMaterial toneMapped={false} />
    </instancedMesh>
  );
}

export default function Backdrop() {
  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden">
      <Canvas
        camera={{ position: [0, 3.4, 7.2], fov: 42 }}
        dpr={[1, 1.6]}
        gl={{ antialias: true, alpha: true }}
        style={{ opacity: 0.38 }}
      >
        <group rotation={[0, Math.PI / 9, 0]}>
          <BarField />
        </group>
      </Canvas>
      <div className="absolute inset-0 bg-gradient-to-b from-ink via-ink/60 to-ink" />
      <div className="absolute inset-x-0 top-0 h-32 bg-gradient-to-b from-ink to-transparent" />
      <div className="absolute inset-y-0 left-0 w-1/2 bg-gradient-to-r from-ink via-ink/70 to-transparent" />
    </div>
  );
}
