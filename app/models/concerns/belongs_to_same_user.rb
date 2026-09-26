# Ownership of a foreign key is not something a controller can be trusted to
# remember. The API controllers check it (Api::V1::TransactionsController's
# verify_ownership!), the web controllers historically did not, and the gap was
# exploitable: permitting :account_id straight from params let one user attach a
# row to another user's account and read that account's name and currency back
# through the API serializers.
#
# Declaring it on the model closes every path at once, including paths that do
# not exist yet.
module BelongsToSameUser
  extend ActiveSupport::Concern

  class_methods do
    def belongs_to_same_user(*names)
      validate do
        names.each do |name|
          related = public_send(name)
          next if related.nil?
          next if related.user_id == user_id

          errors.add(:"#{name}_id", :must_belong_to_same_user)
        end
      end
    end
  end
end
