# Make sure you have the raw resin image ready in DEPLOY_DIR_IMAGE (poky
# krogoth/morty/pyro has the raw image in the deploy dir image after the
# do_image_complete task has been finished)
IMAGE_DEPENDS_balenaos-img_append = " balena-image:do_image_complete"
