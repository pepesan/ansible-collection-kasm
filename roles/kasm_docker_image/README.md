# kasm_docker_image

**Fully qualified name:** `pepesan.kasm.kasm_docker_image` (collection [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Pulls or removes a Docker image inside Kasm's DinD (`docker exec kasm docker
...`), independent of whether that image is registered as a Kasm workspace.
Split out of [`kasm_workspace`](../kasm_workspace/README.md), which used to
pull the image as part of creating a workspace and remove+prune it as part
of deleting one — now a workspace's lifecycle (the `images` table row,
staging, persistent profile) and the underlying Docker image's lifecycle are
two separate, composable steps.

Idempotent: checks `docker image inspect` first, so pulling an
already-present image or removing an already-absent one is a no-op.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `kasm_docker_image_name` | `pepesan/core-ubuntu-resolute:1.20` when `present` (follows `kasm_workspace_image`); **required** when `absent` | e.g. `user/image:tag`. Removing never falls back to a default |
| `kasm_docker_image_state` | `present` | `present` pulls if missing; `absent` removes if present |
| `kasm_docker_image_prune_after_remove` | `true` | Also run `docker image prune -f` after removing (absent only) |

`state: absent` fails if a workspace still references the image or a
session still uses it (Docker refuses to remove an image in use) — delete
the [`kasm_workspace`](../kasm_workspace/README.md) registration first.

## Example


Pull an image into Kasm's Docker ahead of time, so the first session does not wait for the download, and register it as a
workspace:

```yaml
- hosts: ubuntu
  roles:
    - role: pepesan.kasm.kasm_docker_image
      vars:
        kasm_docker_image_name: "user/my-image:1.0"
        kasm_docker_image_state: present
    - role: pepesan.kasm.kasm_workspace
      vars:
        kasm_workspace_state: present
        kasm_workspace_image: "user/my-image:1.0"
        kasm_workspace_name: "My workspace"
```

With no name given, the default image is pulled: `pepesan/core-ubuntu-resolute:1.20`.

```yaml
- hosts: ubuntu
  roles:
    - pepesan.kasm.kasm_docker_image
```

Remove an image. Delete the workspace and its sessions first, otherwise the role fails on purpose; removing never uses a
default image, so the name is required:

```yaml
- hosts: ubuntu
  roles:
    - role: pepesan.kasm.kasm_docker_image
      vars:
        kasm_docker_image_name: "user/my-image:1.0"
        kasm_docker_image_state: absent
```

```bash
docker exec kasm docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}'    # on the server
```
