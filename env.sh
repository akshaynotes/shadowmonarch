if [ "$HUGO_ENV" = "production" ]
then
   export BASE_URL="https://shadowmonarch.com"
else
   export BASE_URL="${DEPLOY_PRIME_URL}"
fi