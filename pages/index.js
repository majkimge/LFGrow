import { Post } from "../components/post"
import picture from "../assets/images/profilePic.png"

export default function HomePage() {
    return (
        <div>
            <h1 className="text-3xl font-bold underline">Reddit clone</h1>
            <Post communityPicture={picture} communityName='Poland' image={picture} titleText='Good news from Poland' author='Andrew' />
        </div>
    )
}