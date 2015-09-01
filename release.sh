#!/bin/bash

set -ueo pipefail

# Constants
api="https://quay.io/api/v1"
started_at=$(date +%s)

## Read input and env
version="$1"
# Base images
base_images="$BASE_IMAGES"
base_dirs="${BASE_DIRS:-$base_images}"
# Service images
service_images="$SERVICE_IMAGES"
service_dirs="${SERVICE_DIRS:-$service_images}"
# Remotes, auth
docker_organization="$DOCKER_ORGANIZATION"
oauth2_token="$OAUTH2_TOKEN"
git_remote="${GIT_REMOTE:-origin}"

prefix() {
    while read line; do
        echo "[$(date +"%x %T")][${1}] $line"
    done
}

bump-zipkin-version () {
    local version="$1"; shift
    local images="$@"
    for image in $images; do
        echo "Bumping ZIPKIN_VERSION in the Dockerfile of $image..."
        dockerfile="${image}/Dockerfile"
        sed -i.bak -e "s/ENV ZIPKIN_VERSION .*/ENV ZIPKIN_VERSION ${version}/" "$dockerfile"
        rm "${dockerfile}.bak"
        git add "$dockerfile"
    done

    git commit -m "Bump ZIPKIN_VERSION to $version"
    git push
}

create-and-push-tag () {
    local tag="$1"
    echo "Creating and pushing tag $tag..."
    git tag "$tag" --force
    git push "$git_remote" "$tag" --force
}

fetch-last-build () {
    local tag="$1"
    local image="$2"
    local repo="${docker_organization}/${image}"

    curl -s "${api}/repository/${repo}/build/" | jq ".builds | map(select(.tags | contains([\"${tag}\"])))[0]"
}

build-started-after-me () {
    local build="$1"

    build_started_at_str="$(echo "$build" | jq '.started' -r)"
    build_started_at="$(date --date "$build_started_at_str" +%s)"
    [[ "$started_at" -lt "$build_started_at" ]] || return 1
}

wait-for-build-to-start () {
    local tag="$1"
    local image="$2"
    local repo="${docker_organization}/${image}"

    timeout=300
    while [[ "$timeout" -gt 0 ]]; do
        echo >&2 "Waiting for the build of $image for version $tag to start for $timeout more seconds..."
        build="$(fetch-last-build "$tag" "$image")"
        if [[ "$build" != "null" ]] && build-started-after-me "$build"; then
            build_id=$(echo "$build" | jq '.id' -r)
            echo >&2 "Build started: https://quay.io/repository/$repo/build/$build_id"
            echo "$build_id"
            return
        fi
        timeout=$(($timeout - 10))
        sleep 10
    done

    echo "Build didn't start in a minute (or I failed to recognized it). Bailing out."
    return 1
}

wait-for-build-to-finish () {
    local image="$1"
    local build_id="$2"

    echo "Waiting for build of $image with tag $tag to finish..."
    while true; do
        phase="$(curl -s "${api}/repository/${docker_organization}/${image}/build/${build_id}" | jq '.phase' -r)"
        if [[ "$phase" == 'complete' ]]; then
            echo "Build completed."
            return
        elif [[ "$phase" == 'error' ]]; then
            echo "Build failed. Bailing out."
            exit 1
        else
            echo "Build of $image is in phase \"${phase}\", waiting..."
            sleep 10
        fi
    done
}

wait-for-builds () {
    local tag="$1"; shift
    local images="$@"
    for image in $images; do
        echo "Waiting for build of $image with tag $tag"
        build_id="$(wait-for-build-to-start "$tag" "$image")"
        wait-for-build-to-finish "$image" "$build_id"
    done
}

sync-quay-tag () {
    local repo="${docker_organization}/$1"
    local reference_tag="$2"
    local tag_to_move="$3"

    echo "Syncing tag ${tag_to_move} to ${reference_tag} on ${repo}"
    image_id="$(curl -s "${api}/repository/${repo}/tag/${reference_tag}/images" | jq '.images | sort_by(-.sort_index)[0].id' -r)"
    echo "Image id is ${image_id}"
    curl -s "${api}/repository/${repo}/tag/${tag_to_move}" \
         -H "Authorization: Bearer $oauth2_token" \
         -H "Content-Type: application/json" \
         -XPUT -d "{\"image\": \"$image_id\"}"
    echo
}

sync-quay-tags () {
    local subminor_tag="$1"; shift
    local minor_tag="$1"; shift
    local major_tag="$1"; shift
    local images="$@"

    for image in $images; do
        sync-quay-tag "$image" "$subminor_tag" "$minor_tag"
        sync-quay-tag "$image" "$subminor_tag" "$major_tag"
    done
}

bump-dockerfiles () {
    local tag="$1"; shift
    local images="$@"
    for image in $images; do
        echo "Bumping base image of $image to $tag"
        dockerfile="${image}/Dockerfile"
        FROM_line_without_tag="$(grep -E '^FROM ' "$dockerfile" | cut -f1 -d:)"
        sed -i.bak -e "s~^FROM .*~${FROM_line_without_tag}:${tag}~" "$dockerfile"
        rm "${dockerfile}.bak"
        git add "$dockerfile"
    done
    git commit -m "Bump base image version of services to ${tag}"
    git push
}

bump-docker-compose-yml () {
    local tag="$1"; shift
    local images="$@"
    for image in $images; do
        echo "Bumping version of $image to $tag in docker-compose.yml"
    done
}

sync-to-dockerhub () {
    local tag="$1"; shift
    local images="$@"
    for image in $images; do
        dockerhub_name="${docker_organization}/${image}:${tag}"
        quay_name="quay.io/${dockerhub_name}"
        echo "Syncing ${quay_name} to Docker Hub as ${dockerhub_name}"
        docker pull "$quay_name"
        docker tag -f "$quay_name" "$dockerhub_name"
        docker push "$dockerhub_name"
    done
}

main () {
    # Check that the version is something we like
    if ! echo "$version" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' -q; then
        echo "Usage: $0 <version>"
        echo "Where version must be <major>.<minor>.<subminor>"
        exit 1
    fi

    # The git tags we'll create
    major_tag=$(echo "$version" | cut -f1 -d. -s)
    minor_tag=$(echo "$version" | cut -f1-2 -d. -s)
    subminor_tag="$version"
    base_tag="base-$version"

    action_plan="
  # bump-zipkin-version     $version $base_dirs                                 2>&1 | prefix bump-zipkin-version
    create-and-push-tag     $base_tag                                           2>&1 | prefix tag-base-image
    wait-for-builds         $base_tag $base_images                              2>&1 | prefix wait-for-base-build
    bump-dockerfiles        $base_tag $service_dirs                             2>&1 | prefix bump-dockerfiles
    create-and-push-tag     $subminor_tag                                       2>&1 | prefix tag-service-images
    wait-for-builds         $subminor_tag $service_images                       2>&1 | prefix wait-for-service-builds
    sync-quay-tags          $subminor_tag $minor_tag $major_tag $service_images 2>&1 | prefix sync-quay-tags
    sync-to-dockerhub       $base_tag $base_images                              2>&1 | prefix sync-base-image-to-dockerhub
    sync-to-dockerhub       $subminor_tag $service_images                       2>&1 | prefix sync-${subminor_tag}-to-dockerhub
    sync-to-dockerhub       $minor_tag $service_images                          2>&1 | prefix sync-${minor_tag}-to-dockerhub
    sync-to-dockerhub       $major_tag $service_images                          2>&1 | prefix sync-${major_tag}-to-dockerhub
    bump-docker-compose-yml $subminor_tag $service_images                       2>&1 | prefix bump-docker-compose-yml
    "

    echo "Starting release $version. Action plan:"
    echo "$action_plan" | sed -e 's/ *2>&1 \| prefix.*//'

    eval "$action_plan"

    echo
    echo "All done. Validate that the Zipkin started by 'docker-compose up' works, then:"
    echo
    echo "    git commit docker-compose.yml -m 'Release $version'; git push"
}

main

